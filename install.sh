#!/bin/bash

# User-level, idempotent installer for Omarchy Delight. Never needs sudo.
# DELIGHT_DRY_RUN=1 prints every side effect as "DRY: <action>" instead.

set -euo pipefail

DELIGHT_ROOT=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
# shellcheck source=lib/delight/delight.sh
source "$DELIGHT_ROOT/lib/delight/delight.sh"

((EUID != 0)) || delight_die "run install.sh as your user, not root"
delight_has_cmd jq || delight_die "jq is required (sudo pacman -S jq)"

if [[ $(readlink -f -- "$DELIGHT_HOME_DIR" 2>/dev/null) != "$DELIGHT_ROOT" ]]; then
  [[ ! -e $DELIGHT_HOME_DIR || -L $DELIGHT_HOME_DIR ]] \
    || delight_die "$DELIGHT_HOME_DIR exists and is not this checkout; move it aside first"
  delight_symlink "$DELIGHT_ROOT" "$DELIGHT_HOME_DIR"
fi
delight_symlink "$DELIGHT_HOME_DIR/bin/delight" "$DELIGHT_BIN_LINK"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) delight_warn "$HOME/.local/bin is not on PATH; add it so 'delight' resolves" ;;
esac

delight_state_init core
delight_config_init

if ! cmp -s "$DELIGHT_ROOT/systemd/delight.target" "$DELIGHT_UNIT_DIR/delight.target"; then
  delight_copy "$DELIGHT_ROOT/systemd/delight.target" "$DELIGHT_UNIT_DIR/delight.target"
  delight_systemd_reload
fi
if ! systemctl --user is-enabled --quiet delight.target 2>/dev/null; then
  delight_run_quiet systemctl --user enable delight.target 2>/dev/null || delight_warn "could not enable delight.target"
fi

delight_plugin_install core "$DELIGHT_ROOT/plugins/control-center"
delight_touchpoints_sync

delight_log "installed. Try: delight list"
