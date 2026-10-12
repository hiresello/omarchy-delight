#!/bin/bash

# Live acceptance check against a real Hyprland (VM or desktop): start adds
# DELIGHT-SIDECAR at the requested mode, stop removes it and leaves the other
# monitors unchanged. Skipped when no Hyprland session is reachable.
# Uses a throwaway HOME, so the real Delight install and Sunshine are untouched.

# shellcheck source=../../../tests/lib/tap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"

sig=${HYPRLAND_INSTANCE_SIGNATURE:-}
if [[ -z $sig ]] || ! hyprctl version >/dev/null 2>&1; then
  echo "1..0 # SKIP no Hyprland session"
  exit 0
fi

BIN="$DELIGHT_TEST_REPO/modules/sidecar/bin/delight-sidecar"
real_path=$PATH
sandbox
export HYPRLAND_INSTANCE_SIGNATURE=$sig
# Stubs only for package/firewall/systemd side effects; hyprctl stays real.
export PATH="$DELIGHT_TEST_REPO/modules/sidecar/tests/stubs:$DELIGHT_TEST_REPO/tests/stubs:$real_path"
hyprctl_bin=$(PATH=$real_path command -v hyprctl)
mkdir -p "$SANDBOX/bin"
ln -s "$hyprctl_bin" "$SANDBOX/bin/hyprctl"
printf '#!/bin/bash\nexit 0\n' >"$SANDBOX/bin/sunshine"
chmod +x "$SANDBOX/bin/sunshine"
export PATH="$SANDBOX/bin:$PATH"

others() {
  hyprctl monitors -j | jq -c '[.[] | select(.name != "DELIGHT-SIDECAR") | {name, width, height, refreshRate, x, y, scale, transform}]'
}

before=$(others)
ok "install (sandboxed)" "$BIN" install
ok "set preset ipad-11" "$BIN" set preset ipad-11
ok "start" "$BIN" start
is "DELIGHT-SIDECAR at 2388x1668@120 scale 2" \
  "$(hyprctl monitors -j | jq -c '.[] | select(.name == "DELIGHT-SIDECAR") | [.width, .height, (.refreshRate | round), .scale]')" \
  "[2388,1668,120,2]"
is "other monitors unchanged after start" "$(others)" "$before"
ok "stop" "$BIN" stop
is "DELIGHT-SIDECAR removed" "$(hyprctl monitors -j | jq '[.[] | select(.name == "DELIGHT-SIDECAR")] | length')" "0"
is "other monitors unchanged after stop" "$(others)" "$before"
ok "uninstall" "$BIN" uninstall

done_testing
