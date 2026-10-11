#!/bin/bash

# ~/.config/omarchy-delight/config.json: {"schema":1,"modules":{"<id>":{"enabled":false,...}}}
# Defaults come from modules/<id>/defaults.json. Writes are serialized with flock.

DELIGHT_CONFIG_EMPTY='{"schema":1,"modules":{}}'

delight_config_init() {
  [[ -f $DELIGHT_CONFIG_FILE ]] && return 0
  jq . <<<"$DELIGHT_CONFIG_EMPTY" | delight_write "$DELIGHT_CONFIG_FILE"
}

delight_config_read() {
  if [[ -f $DELIGHT_CONFIG_FILE ]]; then
    cat -- "$DELIGHT_CONFIG_FILE"
  else
    printf '%s\n' "$DELIGHT_CONFIG_EMPTY"
  fi
}

# delight_config_get <id> <key[.sub]>: prints the value (strings raw, others as JSON).
delight_config_get() {
  local id="$1" key="$2" value defaults
  value=$(delight_config_read | jq -c --arg id "$id" --arg k "$key" 'getpath(["modules", $id] + ($k | split(".")))')
  if [[ $value == "null" ]]; then
    defaults="$DELIGHT_MODULES_DIR/$id/defaults.json"
    if [[ -f $defaults ]]; then
      value=$(jq -c --arg k "$key" 'getpath($k | split("."))' "$defaults")
    fi
  fi
  [[ $value == "null" ]] && return 1
  jq -r . <<<"$value"
}

# Run a jq filter over config.json under an exclusive lock.
delight_config_mutate() {
  local filter="$1" lock fd
  shift
  if delight_dry; then
    delight_dry_print config "$filter" "$@"
    return 0
  fi
  mkdir -p -- "$DELIGHT_RUNTIME_DIR" "$DELIGHT_CONFIG_DIR"
  lock="$DELIGHT_RUNTIME_DIR/config.lock"
  exec {fd}>"$lock"
  flock -x "$fd"
  delight_config_read | jq "$@" "$filter" | delight_write "$DELIGHT_CONFIG_FILE"
  exec {fd}>&-
}

# delight_config_set <id> <key[.sub]> <value>: value is parsed as JSON when it is valid JSON.
delight_config_set() {
  local id="$1" key="$2" value="$3" json
  if json=$(jq -ce . <<<"$value" 2>/dev/null) && [[ -n $json ]] && (($(wc -l <<<"$json") == 1)); then
    :
  else
    json=$(jq -cn --arg v "$value" '$v')
  fi
  delight_config_mutate 'setpath(["modules", $id] + ($k | split(".")); $v)' --arg id "$id" --arg k "$key" --argjson v "$json"
}

delight_config_unset_module() {
  [[ -f $DELIGHT_CONFIG_FILE ]] || return 0
  delight_config_read | jq -e --arg id "$1" '.modules | has($id)' >/dev/null || return 0
  delight_config_mutate 'del(.modules[$id])' --arg id "$1"
}
