#!/bin/bash

# Proves the VM harness on a real Omarchy desktop: Delight, as installed by
# vm/install-delight, registers its Control Center plugin, answers status,
# keeps Hyprland's config error-free, and uninstalls back to the pristine
# hyprland.lua byte for byte. Reinstalls at the end.

[[ ${DELIGHT_VM:-} == 1 ]] || {
  echo "1..0 # SKIP runs inside the Delight VM (vm/run)"
  exit 0
}
# shellcheck source=vm/lib/guest.sh
source "$DELIGHT_VM_LIB"
# shellcheck source=tests/lib/tap.sh
source "$DELIGHT_ROOT/tests/lib/tap.sh"

hypr=$HOME/.config/hypr/hyprland.lua
pristine=$DELIGHT_VM_PRISTINE/.config/hypr/hyprland.lua
marker='>>> omarchy-delight >>>'

config_errors() { hyprctl -j configerrors | jq '[.[] | select(. != "")] | length'; }
plugin_listed() { omarchy plugin list | grep -Eq '^delight\.control-center[[:space:]]'; }
plugin_enabled() { omarchy plugin list | grep -Eq '^delight\.control-center[[:space:]]+enabled'; }

# TAP TODO: reported, but not counted as a failure.
todo() { # <description> <command...>
  local desc=$1
  shift
  TAP_COUNT=$((TAP_COUNT + 1))
  if "$@" >/dev/null 2>&1; then
    echo "ok $TAP_COUNT - $desc # TODO passes now; make it a plain ok"
  else
    echo "not ok $TAP_COUNT - $desc # TODO"
  fi
}

ok "the session has a Wayland display" test -S "$XDG_RUNTIME_DIR/${WAYLAND_DISPLAY:-none}"
ok "delight is on PATH" command -v delight
ok "hyprland.lua carries the Delight block" grep -qF "$marker" "$hypr"
ok "a pristine hyprland.lua was saved before install" test -f "$pristine"
ok "omarchy plugin list shows delight.control-center" plugin_listed
# install.sh enables the plugin before the running shell has rescanned it.
todo "delight.control-center is enabled" plugin_enabled

status=$(delight status --json)
is "delight status --json exits 0" "$?" 0
ok "delight status --json is a JSON array" jq -e 'type == "array"' <<<"$status"

is "hyprctl reload" "$(hyprctl reload)" ok
is "Hyprland reports no config errors" "$(config_errors)" 0
vm_screenshot installed

"$DELIGHT_ROOT/uninstall.sh" >/dev/null 2>&1
is "uninstall.sh exits 0" "$?" 0
ok "uninstall restores hyprland.lua byte for byte" cmp -s "$pristine" "$hypr"
not_ok "delight.control-center is gone from omarchy plugin list" plugin_listed
not_ok "delight is gone from PATH" command -v delight
is "hyprctl reload after uninstall" "$(hyprctl reload)" ok
is "no config errors after uninstall" "$(config_errors)" 0
vm_screenshot uninstalled

(cd "$DELIGHT_ROOT" && ./install.sh) >/dev/null 2>&1
is "reinstall exits 0" "$?" 0
ok "the Delight block is back" grep -qF "$marker" "$hypr"

done_testing
