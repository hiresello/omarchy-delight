#!/bin/bash

source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/test-lib"

hotspot_test_init
hotspot_nm_fixture
hotspot_bt_fixture
export DELIGHT_SYSFS="$SANDBOX/no-adapter"
bin="$DELIGHT_TEST_REPO/modules/hotspot/bin/delight-hotspot"
hotspot_install
other_before=$(jq -c '[.connections[] | select(.uuid != "hotspot-uuid")]' "$DELIGHT_STUB_STATE/nm.json")

hotspot_setup
is "setup works without a Bluetooth adapter" \
  "$(jq -r '.modules.hotspot.phone.mac' "$HOME/.config/omarchy-delight/config.json")" \
  "AA:BB:CC:DD:EE:FF"
is "target priority is below every other profile" "$(jq -r '.connections[] | select(.uuid == "hotspot-uuid") | .priority' "$DELIGHT_STUB_STATE/nm.json")" "-4"
is "target autoconnect is enabled" "$(jq -r '.connections[] | select(.uuid == "hotspot-uuid") | .autoconnect' "$DELIGHT_STUB_STATE/nm.json")" "yes"
is "target profile is metered" "$(jq -r '.connections[] | select(.uuid == "hotspot-uuid") | .metered' "$DELIGHT_STUB_STATE/nm.json")" "yes"
is "other profiles are byte-identical" "$(jq -c '[.connections[] | select(.uuid != "hotspot-uuid")]' "$DELIGHT_STUB_STATE/nm.json")" "$other_before"
ok "exact modify argv is logged" grep -Fq 'nmcli connection modify uuid hotspot-uuid connection.autoconnect yes connection.autoconnect-priority -4 connection.metered yes' "$DELIGHT_STUB_LOG"
is "previous NetworkManager values are recorded" \
  "$(jq -c '.flags.nm.prev' "$HOME/.local/state/omarchy-delight/hotspot/installed.json")" \
  '{"autoconnect":"no","priority":"7","metered":"unknown"}'

prev_before=$(jq -c '.flags.nm.prev' "$HOME/.local/state/omarchy-delight/hotspot/installed.json")
hotspot_setup
is "rerun keeps original values" "$(jq -c '.flags.nm.prev' "$HOME/.local/state/omarchy-delight/hotspot/installed.json")" "$prev_before"

if command -v omarchy-shell >/dev/null 2>&1; then
  dry_open=$(DELIGHT_DRY_RUN=1 "$bin" setup 2>&1)
  ok "setup without selections opens the panel in dry-run" \
    grep -Fq "DRY: $DELIGHT_TEST_REPO/bin/delight ui summon delight.hotspot" <<<"$dry_open"
else
  set +e
  "$bin" setup >/dev/null 2>&1
  rc=$?
  set -e
  is "non-interactive setup without selections exits 64" "$rc" "64"
fi

"$bin" setup --ssid Home --bt AA:BB:CC:DD:EE:FF --no-enable
is "switch restores the former profile" \
  "$(jq -c '.connections[] | select(.uuid == "hotspot-uuid") | [.autoconnect,.priority,.metered]' "$DELIGHT_STUB_STATE/nm.json")" \
  '["no",7,"unknown"]'
"$bin" uninstall
is "uninstall restores selected profile" \
  "$(jq -c '.connections[] | select(.uuid == "home-uuid") | [.autoconnect,.priority,.metered]' "$DELIGHT_STUB_STATE/nm.json")" \
  '["yes",5,"no"]'

hotspot_install
jq '(.connections[] | select(.uuid == "low-uuid") | .priority) = -999' \
  "$DELIGHT_STUB_STATE/nm.json" >"$DELIGHT_STUB_STATE/nm.tmp"
mv "$DELIGHT_STUB_STATE/nm.tmp" "$DELIGHT_STUB_STATE/nm.json"
"$bin" setup --ssid TestHotspot --bt AA:BB:CC:DD:EE:FF --no-enable
is "priority clamps at NetworkManager minimum" \
  "$(jq -r '.connections[] | select(.uuid == "hotspot-uuid") | .priority' "$DELIGHT_STUB_STATE/nm.json")" "-999"
"$bin" uninstall

before=$(jq -c . "$DELIGHT_STUB_STATE/nm.json")
set +e
"$bin" setup --ssid Missing --bt AA:BB:CC:DD:EE:FF --no-enable >/dev/null 2>&1
rc=$?
set -e
is "unknown non-interactive SSID exits 3" "$rc" "3"
is "unknown SSID leaves NetworkManager unchanged" "$(jq -c . "$DELIGHT_STUB_STATE/nm.json")" "$before"

dry=$(DELIGHT_DRY_RUN=1 "$bin" setup --ssid TestHotspot --bt AA:BB:CC:DD:EE:FF --no-enable 2>&1)
ok "dry-run prints the exact modify command" grep -Fq \
  'DRY: nmcli connection modify uuid hotspot-uuid connection.autoconnect yes connection.autoconnect-priority -999 connection.metered yes' \
  <<<"$dry"
is "dry-run leaves NetworkManager unchanged" "$(jq -c . "$DELIGHT_STUB_STATE/nm.json")" "$before"

"$bin" setup --ssid TestHotspot --bt AA:BB:CC:DD:EE:FF --no-enable
: >"$DELIGHT_STUB_LOG"
"$bin" connect
ok "connect brings up configured UUID" grep -Fq 'nmcli connection up uuid hotspot-uuid' "$DELIGHT_STUB_LOG"

done_testing
