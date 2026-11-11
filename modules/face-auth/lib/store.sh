#!/bin/bash

# Face-template storage checks.
# Encryption is "the directory sits on dm-crypt / LUKS". This does not add a
# second key. Howdy Next has to read the templates as root at unlock time, so a
# key root can use is also a key root malware can use. Permissions are still
# tightened: root (or the test uid), no group or other bits, no symlinks.

# Longest mount point in a mounts(5) file that prefixes the path.
# Prints "source fstype" or nothing.
face_auth_mount_of() {
  local path="$1" mounts="$2" best="" source="" fstype="" point rest src typ slash
  [[ -f $mounts ]] || return 1
  while read -r src point typ rest; do
    [[ -n ${src:-} && $src != \#* ]] || continue
    slash="${point%/}"
    [[ $path == "$point" || $path == ${slash}/* ]] || continue
    if [[ ${#point} -gt ${#best} ]]; then
      best=$point
      source=$src
      fstype=$typ
    fi
  done <"$mounts"
  [[ -n $best ]] || return 1
  printf '%s %s\n' "$source" "$fstype"
}

# 0 when the path's mount looks like full-disk encryption.
face_auth_path_encrypted() {
  local path="$1" mounts="$2" source fstype
  source=$(face_auth_mount_of "$path" "$mounts") || return 1
  fstype=${source#* }
  source=${source%% *}
  [[ $source == /dev/mapper/* || $source == *crypt* || $fstype == crypt || $fstype == ecryptfs ]]
}

face_auth_mode_private() {
  local mode="$1" kind="$2"
  mode=$((8#$mode))
  if ((mode & 077)); then
    return 1
  fi
  [[ $kind == dir || $kind == file ]]
}

# Audit one existing path. expected_uid is the only acceptable owner.
# Does not change the path.
face_auth_audit_path() {
  local path="$1" uid="$2" mode owner kind
  if [[ -L $path ]]; then
    printf 'model-symlink: %s\n' "$path" >&2
    return 1
  fi
  if [[ -d $path ]]; then
    kind="dir"
  elif [[ -f $path ]]; then
    kind="file"
  else
    printf 'model-special: %s\n' "$path" >&2
    return 1
  fi
  mode=$(stat -c %a -- "$path")
  owner=$(stat -c %u -- "$path")
  if [[ $owner != "$uid" ]]; then
    printf 'model-owner: %s owner=%s\n' "$path" "$owner" >&2
    return 1
  fi
  if ! face_auth_mode_private "$mode" "$kind"; then
    printf 'model-mode: %s mode=%s\n' "$path" "$mode" >&2
    return 1
  fi
}

# Audit Howdy's template locations if they exist under root.
# Candidate trees are the ones that hold enrolled faces, not the OpenCV nets.
face_auth_audit_models() {
  local root="$1" uid="$2" rel path item rc=0
  local -a roots=(
    etc/howdy/models
    var/lib/howdy
    usr/lib/security/howdy/models
    usr/lib64/security/howdy/models
  )
  for rel in "${roots[@]}"; do
    path="$root/$rel"
    [[ -e $path || -L $path ]] || continue
    face_auth_audit_path "$path" "$uid" || return 1
    while IFS= read -r -d '' item; do
      face_auth_audit_path "$item" "$uid" || return 1
    done < <(find -P "$path" -mindepth 1 -print0 2>/dev/null)
  done
  path="$root/etc/howdy/config.ini"
  if [[ -e $path || -L $path ]]; then
    face_auth_audit_path "$path" "$uid" || return 1
  fi
  return "$rc"
}

# chmod (and chown when we are root) then audit. Refuses symlinks.
face_auth_tighten_models() {
  local root="$1" uid="$2" rel path item
  local -a roots=(
    etc/howdy/models
    var/lib/howdy
    usr/lib/security/howdy/models
    usr/lib64/security/howdy/models
  )
  for rel in "${roots[@]}"; do
    path="$root/$rel"
    [[ -e $path || -L $path ]] || continue
    if [[ -L $path ]]; then
      printf 'model-symlink: %s\n' "$path" >&2
      return 1
    fi
    [[ -d $path ]] || {
      printf 'model-special: %s\n' "$path" >&2
      return 1
    }
    chmod 0700 -- "$path" || return 1
    if [[ $EUID -eq 0 ]]; then
      chown 0:0 -- "$path" || return 1
    fi
    while IFS= read -r -d '' item; do
      if [[ -L $item ]]; then
        printf 'model-symlink: %s\n' "$item" >&2
        return 1
      elif [[ -d $item ]]; then
        chmod 0700 -- "$item" || return 1
      elif [[ -f $item ]]; then
        chmod 0600 -- "$item" || return 1
      else
        printf 'model-special: %s\n' "$item" >&2
        return 1
      fi
      if [[ $EUID -eq 0 ]]; then
        chown 0:0 -- "$item" || return 1
      fi
    done < <(find -P "$path" -mindepth 1 -print0)
  done
  path="$root/etc/howdy/config.ini"
  if [[ -L $path ]]; then
    printf 'model-symlink: %s\n' "$path" >&2
    return 1
  fi
  if [[ -f $path ]]; then
    chmod 0600 -- "$path" || return 1
    if [[ $EUID -eq 0 ]]; then
      chown 0:0 -- "$path" || return 1
    fi
  fi
  face_auth_audit_models "$root" "$uid"
}

# 0 when it is acceptable to install PAM given this mount table.
# allow is the string true/false from the policy.
face_auth_check_encryption() {
  local root="$1" mounts="$2" allow="$3" probe
  probe="$root"
  [[ -d $root/etc ]] && probe="$root/etc"
  if face_auth_path_encrypted "$probe" "$mounts"; then
    return 0
  fi
  if [[ $allow == true ]]; then
    printf 'warning: face templates would not sit on a detected encrypted mount\n' >&2
    return 0
  fi
  printf 'unencrypted: %s\n' "$probe" >&2
  return 1
}
