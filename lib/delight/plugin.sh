#!/bin/bash

# Omarchy shell plugins. Omarchy's validator rejects symlinks inside plugin
# directories, so plugins are staged as plain copies with qml/Delight bundled
# next to the entry points (imported as `import "Delight"`).

# delight_plugin_stage <src-dir> <dest-dir>
delight_plugin_stage() {
  local src="$1" dest="$2"
  rm -rf -- "$dest"
  mkdir -p -- "$dest"
  cp -rL -- "$src"/. "$dest"/
  rm -rf -- "$dest/Delight"
  cp -rL -- "$DELIGHT_ROOT/qml/Delight" "$dest/Delight"
}

# A running shell only knows the plugins it has scanned: enabling a new one
# fails and a removed one stays listed until it rescans.
delight_plugin_rescan() {
  if ! delight_dry && delight_has_cmd omarchy-shell; then
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi
}

delight_plugin_id() {
  jq -r '.id' "$1/manifest.json"
}

delight_plugin_is_enabled() {
  omarchy plugin list 2>/dev/null | grep -Eq "^${1}[[:space:]].*enabled"
}

# The shell drops a rescan that arrives while another is still running, and
# `omarchy plugin enable` fails for a plugin it hasn't seen, so retry both.
delight_plugin_enable_retry() {
  local pid="$1" try
  for try in 1 2 3 4 5 6 7 8 9 10; do
    delight_plugin_rescan
    delight_plugin_is_enabled "$pid" && return 0
    if delight_run_quiet omarchy plugin enable "$pid" && delight_plugin_is_enabled "$pid"; then
      return 0
    fi
    if delight_dry; then
      return 0
    fi
    sleep 1
  done
  delight_warn "could not enable plugin $pid after $try attempts"
}

# delight_plugin_install <owner-id> <src-dir>: copy into ~/.config/omarchy/plugins/<plugin-id> and enable.
delight_plugin_install() {
  local owner="$1" src="$2" pid dest staged
  pid=$(delight_plugin_id "$src")
  [[ $pid == delight.* ]] || delight_die "$owner: plugin id '$pid' must start with delight."
  dest="$DELIGHT_PLUGIN_DIR/$pid"
  staged=$(mktemp -d)
  delight_plugin_stage "$src" "$staged/$pid"
  if [[ -d $dest ]] && diff -rq -- "$staged/$pid" "$dest" >/dev/null 2>&1; then
    rm -rf -- "$staged"
  elif delight_dry; then
    rm -rf -- "$staged"
    delight_dry_print install-plugin "$pid" "$dest"
  else
    mkdir -p -- "$DELIGHT_PLUGIN_DIR"
    rm -rf -- "$dest"
    mv -- "$staged/$pid" "$dest"
    rm -rf -- "$staged"
  fi
  delight_state_add "$owner" plugins "$(jq -cn --arg p "$pid" '$p')"
  if delight_has_cmd omarchy; then
    delight_plugin_enable_retry "$pid"
  else
    delight_log "omarchy not found; enable $pid later with: omarchy plugin enable $pid"
  fi
}

delight_plugin_remove_all() {
  local owner="$1" entry pid removed=0
  while IFS= read -r entry; do
    [[ -n $entry ]] || continue
    pid=$(jq -r '.' <<<"$entry")
    if delight_has_cmd omarchy; then
      delight_run_quiet omarchy plugin disable "$pid" 2>/dev/null || true
    fi
    delight_rm "$DELIGHT_PLUGIN_DIR/$pid"
    delight_state_del "$owner" plugins "$entry"
    removed=1
  done < <(delight_state_list "$owner" plugins)
  if ((removed)); then
    delight_plugin_rescan
  fi
}
