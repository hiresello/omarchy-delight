#!/bin/bash

# Install or roll back the rendered stack under ${FACE_AUTH_ROOT:-}.
# An empty FACE_AUTH_ROOT means the real system and requires root.
# Apply refuses to write /etc/pam.d until the rendered stack validates and the
# template directory is on an encrypted mount (unless the policy says otherwise).

face_auth_base() {
  printf '%s/var/lib/omarchy-delight/face-auth\n' "${FACE_AUTH_ROOT:-}"
}

face_auth_manifest() {
  printf '%s/manifest\n' "$(face_auth_base)"
}

face_auth_backup_name() {
  local path="$1"
  printf '%s\n' "${path//\//_}"
}

face_auth_log() {
  if command -v logger >/dev/null 2>&1; then
    logger -t delight-face-auth -- "$*" || true
  fi
  printf 'face-auth: %s\n' "$*" >&2
}

# Restore whatever the manifest recorded. Idempotent when no manifest exists.
face_auth_rollback() {
  local script root
  root=${FACE_AUTH_ROOT:-}
  script="$root/usr/local/sbin/delight-face-auth-disable"
  if [[ ! -x $script ]]; then
    script=""
  fi
  if [[ -z $script ]]; then
    local manifest
    manifest=$(face_auth_manifest)
    if [[ ! -f $manifest ]]; then
      face_auth_log "already disabled (no manifest)"
      return 0
    fi
    face_auth_log "rollback script is missing; refusing to guess"
    return 1
  fi
  FACE_AUTH_ROOT="$root" "$script"
}

face_auth_read_manifest() {
  local manifest="$1" path action backup
  MANIFEST_PATH=()
  MANIFEST_ACTION=()
  MANIFEST_BACKUP=()
  [[ -f $manifest ]] || return 0
  while IFS=$'\t' read -r path action backup || [[ -n ${path:-} ]]; do
    [[ -n ${path:-} ]] || continue
    [[ $path == \#* || $path == v1 ]] && continue
    MANIFEST_PATH+=("$path")
    MANIFEST_ACTION+=("$action")
    MANIFEST_BACKUP+=("${backup:--}")
  done <"$manifest"
}

face_auth_manifest_index() {
  local path="$1" i
  for i in "${!MANIFEST_PATH[@]}"; do
    [[ ${MANIFEST_PATH[$i]} == "$path" ]] && {
      printf '%s\n' "$i"
      return 0
    }
  done
  return 1
}

# Restore one previously recorded path. Used when a service leaves the policy.
face_auth_restore_one() {
  local root="$1" path="$2" action="$3" backup="$4" dest
  dest="$root$path"
  case "$action" in
    create) rm -f -- "$dest" ;;
    replace)
      [[ -f $(face_auth_base)/backup/$backup ]] || {
        face_auth_log "missing backup for $path"
        return 1
      }
      cp -f -- "$(face_auth_base)/backup/$backup" "$dest"
      ;;
    *)
      face_auth_log "bad manifest action for $path"
      return 1
      ;;
  esac
}

# face_auth_apply_policy <policy-json> <mounts-file> [--dry-run]
face_auth_apply_policy() {
  local policy="$1" mounts="$2" dry=0 root base stage path dest name idx
  [[ ${3:-} == --dry-run ]] && dry=1
  root=${FACE_AUTH_ROOT:-}
  if [[ $dry -eq 0 && -z $root && $EUID -ne 0 ]]; then
    face_auth_log "apply must run as root. Use --dry-run to preview."
    return 1
  fi

  policy=$(face_auth_policy_normalize <<<"$policy") || return 1
  local allow uid
  allow=$(jq -r '.allow_unencrypted_models' <<<"$policy")
  if [[ $EUID -eq 0 ]]; then
    uid=0
  else
    uid=$EUID
  fi

  stage=$(mktemp -d)
  if ! face_auth_render_tree "$policy" "$stage"; then
    rm -rf -- "$stage"
    face_auth_log "rendered stack failed validation; nothing was installed"
    return 1
  fi
  local -a rels=() abs=()
  if [[ -f $stage/pam.d/hyprlock ]]; then
    rels+=(pam.d/hyprlock)
    abs+=(/etc/pam.d/hyprlock)
  fi
  if [[ -f $stage/pam.d/sudo ]]; then
    rels+=(pam.d/sudo)
    abs+=(/etc/pam.d/sudo)
  fi
  if ((${#abs[@]} > 0)); then
    rels+=(lib/face-auth-gate lib/face-auth-stamp system-sleep/omarchy-delight-face-auth)
    abs+=(
      /usr/local/lib/omarchy-delight/face-auth-gate
      /usr/local/lib/omarchy-delight/face-auth-stamp
      /usr/lib/systemd/system-sleep/omarchy-delight-face-auth
    )
  fi

  if ((${#abs[@]} == 0)); then
    rm -rf -- "$stage"
    if [[ $dry -eq 1 ]]; then
      face_auth_log "dry-run: policy enables no service; would roll back an installed stack"
      return 0
    fi
    if [[ -f $(face_auth_manifest) ]]; then
      face_auth_rollback || return 1
    fi
    face_auth_log "face auth is not enabled for any service"
    return 0
  fi

  if ! face_auth_check_encryption "${root:-/}" "$mounts" "$allow"; then
    rm -rf -- "$stage"
    face_auth_log "refusing to apply while the store is not on an encrypted mount"
    return 1
  fi

  local i
  for i in "${!abs[@]}"; do
    dest="$root${abs[$i]}"
    if [[ -L $dest || -L $(dirname -- "$dest") ]]; then
      rm -rf -- "$stage"
      face_auth_log "refusing symlink at $dest"
      return 1
    fi
  done

  if [[ $dry -eq 1 ]]; then
    if ! face_auth_audit_models "$root" "$uid"; then
      rm -rf -- "$stage"
      return 1
    fi
    for i in "${!abs[@]}"; do
      printf 'would install %s\n' "${abs[$i]}"
    done
    printf 'would install %s\n' /usr/local/sbin/delight-face-auth-disable
    rm -rf -- "$stage"
    return 0
  fi

  if ! face_auth_tighten_models "$root" "$uid"; then
    rm -rf -- "$stage"
    face_auth_log "model storage is not safe to keep; PAM was not changed"
    return 1
  fi

  base=$(face_auth_base)
  mkdir -p -- "$base/backup" "$root/etc/pam.d" "$root/usr/local/lib/omarchy-delight" \
    "$root/usr/local/sbin" "$root/usr/lib/systemd/system-sleep"
  chmod 0700 -- "$base" "$base/backup"

  face_auth_read_manifest "$base/manifest"
  local -a new_action=() new_backup=()
  for i in "${!abs[@]}"; do
    path=${abs[$i]}
    dest="$root$path"
    if idx=$(face_auth_manifest_index "$path"); then
      new_action+=("${MANIFEST_ACTION[$idx]}")
      new_backup+=("${MANIFEST_BACKUP[$idx]}")
      if [[ ${MANIFEST_ACTION[$idx]} == replace && ! -f $base/backup/${MANIFEST_BACKUP[$idx]} ]]; then
        rm -rf -- "$stage"
        face_auth_log "missing backup for $path"
        return 1
      fi
    elif [[ -e $dest ]]; then
      name=$(face_auth_backup_name "$path")
      cp -f -- "$dest" "$base/backup/$name"
      new_action+=(replace)
      new_backup+=("$name")
    else
      new_action+=(create)
      new_backup+=("-")
    fi
  done

  local j seen
  for j in "${!MANIFEST_PATH[@]}"; do
    seen=0
    for path in "${abs[@]}"; do
      [[ ${MANIFEST_PATH[$j]} == "$path" ]] && seen=1
    done
    if [[ $seen -eq 0 ]]; then
      if ! face_auth_restore_one "$root" "${MANIFEST_PATH[$j]}" "${MANIFEST_ACTION[$j]}" "${MANIFEST_BACKUP[$j]}"; then
        rm -rf -- "$stage"
        return 1
      fi
    fi
  done

  {
    printf '%s\n' v1
    printf '%s\n' "# path action backup. create files are removed on rollback; replace files are copied back."
    for i in "${!abs[@]}"; do
      printf '%s\t%s\t%s\n' "${abs[$i]}" "${new_action[$i]}" "${new_backup[$i]}"
    done
  } >"$base/manifest"
  chmod 0600 -- "$base/manifest"

  for i in "${!abs[@]}"; do
    cp -f -- "$stage/${rels[$i]}" "$root${abs[$i]}"
  done
  cp -f -- "$stage/sbin/delight-face-auth-disable" "$root/usr/local/sbin/delight-face-auth-disable"
  [[ -f $root/etc/pam.d/hyprlock && -f $stage/pam.d/hyprlock ]] && chmod 0644 -- "$root/etc/pam.d/hyprlock"
  [[ -f $root/etc/pam.d/sudo && -f $stage/pam.d/sudo ]] && chmod 0644 -- "$root/etc/pam.d/sudo"
  chmod 0755 -- \
    "$root/usr/local/lib/omarchy-delight/face-auth-gate" \
    "$root/usr/local/lib/omarchy-delight/face-auth-stamp" \
    "$root/usr/local/sbin/delight-face-auth-disable" \
    "$root/usr/lib/systemd/system-sleep/omarchy-delight-face-auth"

  local service
  for service in hyprlock sudo; do
    [[ -f $stage/pam.d/$service ]] || continue
    if ! face_auth_validate_pam_file "$root/etc/pam.d/$service" "$policy" "$service"; then
      rm -rf -- "$stage"
      face_auth_log "installed stack failed validation; rolling back"
      face_auth_rollback || return 1
      return 1
    fi
  done
  rm -rf -- "$stage"
  face_auth_log "applied ($(jq -r 'if .scope.sudo then "hyprlock and sudo" elif .scope.hyprlock then "hyprlock" else "none" end' <<<"$policy"))"
}

face_auth_manifest_present() {
  [[ -f $(face_auth_manifest) ]]
}
