#!/bin/bash

# systemd user units. Module units are named delight-<id>[-*].service and are
# PartOf=delight.target. Upstream units are only extended with drop-ins.

delight_systemd_reload() {
  delight_run systemctl --user daemon-reload || true
}

# delight_unit_install <id> <unit-file>
delight_unit_install() {
  local id="$1" src="$2" name
  name=$(basename -- "$src")
  [[ $name =~ ^delight-$id(-[a-z0-9-]+)?\.(service|timer|socket|path)$ ]] \
    || delight_die "$id: unit '$name' must be named delight-${id}[-*].service"
  delight_copy "$src" "$DELIGHT_UNIT_DIR/$name"
  delight_state_add "$id" units "$(jq -cn --arg n "$name" '$n')"
}

# delight_unit_dropin <id> <upstream-unit> <conf-file>
delight_unit_dropin() {
  local id="$1" unit="$2" src="$3" dest
  [[ $unit != delight-* ]] || delight_die "$id: use delight_unit_install for Delight's own units"
  dest="$DELIGHT_UNIT_DIR/$unit.d/delight-$id.conf"
  delight_copy "$src" "$dest"
  delight_state_add "$id" files "$(jq -cn --arg f "$dest" '$f')"
}

delight_unit_start() {
  local unit
  for unit in "$@"; do
    delight_run systemctl --user enable --now "$unit" || delight_warn "could not start $unit"
  done
}

delight_unit_stop() {
  local unit
  for unit in "$@"; do
    delight_run systemctl --user disable --now "$unit" >/dev/null 2>&1 || true
  done
}

delight_unit_remove() {
  local id="$1" entry name
  while IFS= read -r entry; do
    [[ -n $entry ]] || continue
    name=$(jq -r '.' <<<"$entry")
    delight_unit_stop "$name"
    delight_rm "$DELIGHT_UNIT_DIR/$name"
    delight_state_del "$id" units "$entry"
  done < <(delight_state_list "$id" units)
  delight_systemd_reload
}

# Files a module copied outside the repo (drop-ins, desktop files, ...).
delight_file_install() {
  local id="$1" src="$2" dest="$3"
  delight_copy "$src" "$dest"
  delight_state_add "$id" files "$(jq -cn --arg f "$dest" '$f')"
}

delight_file_remove_all() {
  local id="$1" entry path
  while IFS= read -r entry; do
    [[ -n $entry ]] || continue
    path=$(jq -r '.' <<<"$entry")
    delight_rm "$path"
    delight_rmdir_empty "$(dirname -- "$path")"
    delight_state_del "$id" files "$entry"
  done < <(delight_state_list "$id" files)
}
