#!/bin/bash

# Paths, logging and small predicates. Sourced by delight.sh.

# shellcheck disable=SC2034 # used by the files that source this one
DELIGHT_HOME_DIR="$HOME/.local/share/omarchy-delight"
DELIGHT_BIN_LINK="$HOME/.local/bin/delight"
DELIGHT_CONFIG_DIR="$HOME/.config/omarchy-delight"
DELIGHT_CONFIG_FILE="$DELIGHT_CONFIG_DIR/config.json"
DELIGHT_STATE_DIR="$HOME/.local/state/omarchy-delight"
DELIGHT_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}/omarchy-delight"
DELIGHT_STATUS_DIR="$DELIGHT_RUNTIME_DIR/status"
DELIGHT_UNIT_DIR="$HOME/.config/systemd/user"
DELIGHT_PLUGIN_DIR="$HOME/.config/omarchy/plugins"
DELIGHT_MODULES_DIR="$DELIGHT_ROOT/modules"
DELIGHT_PRIVATE_CIDRS=(10.0.0.0/8 172.16.0.0/12 192.168.0.0/16)
DELIGHT_MODULE_IDS=(share phone input airplay sync camera sidecar hotspot)

delight_log() {
  printf 'delight: %s\n' "$*" >&2
}

delight_warn() {
  printf 'delight: warning: %s\n' "$*" >&2
}

delight_die() {
  printf 'delight: error: %s\n' "$1" >&2
  exit "${2:-1}"
}

delight_has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

delight_dry() {
  [[ ${DELIGHT_DRY_RUN:-0} == "1" ]]
}

delight_valid_id() {
  [[ $1 =~ ^[a-z][a-z0-9-]*$ ]]
}

delight_module_dir() {
  printf '%s/%s\n' "$DELIGHT_MODULES_DIR" "$1"
}

delight_module_exists() {
  delight_valid_id "$1" && [[ -f $DELIGHT_MODULES_DIR/$1/module.json ]]
}

# Every module directory that has a module.json, sorted by id.
delight_modules() {
  local manifest
  for manifest in "$DELIGHT_MODULES_DIR"/*/module.json; do
    [[ -f $manifest ]] || continue
    basename -- "$(dirname -- "$manifest")"
  done
}

# jq filter against modules/<id>/module.json, e.g. delight_module_field airplay '.name'
delight_module_field() {
  jq -r "$2" "$DELIGHT_MODULES_DIR/$1/module.json"
}
