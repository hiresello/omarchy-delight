#!/bin/bash

# Install records at ~/.local/state/omarchy-delight/<id>/installed.json.
# Uninstall reverses exactly what is recorded here and nothing else.
#   {"schema":1,"packages":[{"name","source"}],"units":[],"firewall":[{"proto","ports","tailscale"}],"files":[],"plugins":[],"flags":{}}

DELIGHT_STATE_EMPTY='{"schema":1,"packages":[],"units":[],"firewall":[],"files":[],"plugins":[],"flags":{}}'

delight_state_file() {
  printf '%s/%s/installed.json\n' "$DELIGHT_STATE_DIR" "$1"
}

delight_is_installed() {
  [[ -f $(delight_state_file "$1") ]]
}

delight_state_get() {
  local file
  file=$(delight_state_file "$1")
  if [[ -f $file ]]; then
    cat -- "$file"
  else
    printf '%s\n' "$DELIGHT_STATE_EMPTY"
  fi
}

delight_state_init() {
  delight_is_installed "$1" && return 0
  printf '%s\n' "$DELIGHT_STATE_EMPTY" | jq . | delight_write "$(delight_state_file "$1")"
}

# delight_state_update <id> <jq-filter> [jq args...]
delight_state_update() {
  local id="$1" filter="$2"
  shift 2
  delight_dry && return 0
  delight_state_init "$id"
  delight_state_get "$id" | jq "$@" "$filter" | delight_write "$(delight_state_file "$id")"
}

# Append a JSON value to a list unless it is already there.
delight_state_add() {
  delight_state_update "$1" '.[$k] |= (if index([$v]) then . else . + [$v] end)' --arg k "$2" --argjson v "$3"
}

delight_state_del() {
  delight_state_update "$1" '.[$k] |= map(select(. != $v))' --arg k "$2" --argjson v "$3"
}

delight_state_list() {
  delight_state_get "$1" | jq -c --arg k "$2" '.[$k][]?'
}

delight_state_flag_get() {
  delight_state_get "$1" | jq -r --arg k "$2" '.flags[$k] // empty'
}

delight_state_flag_set() {
  delight_state_update "$1" '.flags[$k] = $v' --arg k "$2" --argjson v "$3"
}

delight_state_clear() {
  delight_rm "$DELIGHT_STATE_DIR/$1"
}

# Ids (modules or "core") that recorded something under <key> matching <jq-select>.
delight_state_owners() {
  local key="$1" select="$2" file id
  for file in "$DELIGHT_STATE_DIR"/*/installed.json; do
    [[ -f $file ]] || continue
    id=$(basename -- "$(dirname -- "$file")")
    if jq -e --arg k "$key" ".[\$k] | any($select)" "$file" >/dev/null 2>&1; then
      printf '%s\n' "$id"
    fi
  done
}
