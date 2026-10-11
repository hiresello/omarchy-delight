#!/bin/bash

# Reverse install.sh and every module install, restoring touched user files.
# Idempotent; honours DELIGHT_DRY_RUN=1.

set -euo pipefail

DELIGHT_ROOT=$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)
# shellcheck source=lib/delight/delight.sh
source "$DELIGHT_ROOT/lib/delight/delight.sh"

((EUID != 0)) || delight_die "run uninstall.sh as your user, not root"

while IFS= read -r id; do
  delight_log "uninstalling $id"
  "$DELIGHT_ROOT/modules/$id/bin/delight-$id" uninstall || delight_warn "$id: uninstall failed"
done < <(delight_installed_modules)

delight_plugin_remove_all core
delight_touchpoints_remove

if [[ -f $DELIGHT_UNIT_DIR/delight.target ]]; then
  delight_run_quiet systemctl --user disable delight.target 2>/dev/null || true
  delight_rm "$DELIGHT_UNIT_DIR/delight.target"
  delight_systemd_reload
fi

delight_rm "$DELIGHT_CONFIG_DIR"
delight_rm "$DELIGHT_RUNTIME_DIR"
delight_rm "$DELIGHT_STATE_DIR"
[[ -L $DELIGHT_BIN_LINK ]] && delight_rm "$DELIGHT_BIN_LINK"
[[ -L $DELIGHT_HOME_DIR ]] && delight_rm "$DELIGHT_HOME_DIR"

delight_log "uninstalled"
