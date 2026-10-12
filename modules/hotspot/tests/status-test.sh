#!/bin/bash

source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/test-lib"

hotspot_test_init
hotspot_nm_fixture
hotspot_bt_fixture
bin="$DELIGHT_TEST_REPO/modules/hotspot/bin/delight-hotspot"
status=$("$bin" status --json)
is "uninstalled module needs setup" "$(jq -r .state <<<"$status")" "needs-setup"
is "uninstalled status offers install" "$(jq -r '.actions[0].label' <<<"$status")" "Install"
hotspot_install

export DELIGHT_SYSFS="$SANDBOX/no-adapter"
status=$("$bin" status --json)
is "missing adapter reports unsupported" "$(jq -r .state <<<"$status")" "unsupported"
is "missing adapter explains proximity dependency" "$(jq -r .reason <<<"$status")" \
  "No Bluetooth adapter found; Instant Hotspot needs one to tell when your phone is near"
ok "unsupported status matches schema" schema_valid "$DELIGHT_TEST_REPO/schema/status.schema.json" <(printf '%s' "$status")
is "doctor reports unsupported adapter" "$(
  "$bin" doctor >/dev/null 2>&1
  echo $?
)" "2"

export DELIGHT_SYSFS="$SANDBOX/sys"
is "unconfigured doctor asks for setup" "$(
  "$bin" doctor >/dev/null 2>&1
  echo $?
)" "3"
is "devices without a phone is an empty array" "$("$bin" devices --json)" "[]"
candidates=$("$bin" candidates --json)
ok "candidates JSON is valid" jq -e 'type == "object" and (.ssids|type == "array") and (.devices|type == "array") and (.selected|type == "object")' <<<"$candidates"
is "candidates include saved and scanned networks" \
  "$(jq -c '[[.ssids[] | select(.ssid == "TestHotspot") | .saved], [.ssids[] | select(.ssid == "Cafe: Corner") | .signal]]' <<<"$candidates")" \
  '[[true],[64]]'
is "inactive saved profile is not marked active" \
  "$(jq -r '.ssids[] | select(.ssid == "TestHotspot") | .active' <<<"$candidates")" "false"
is "paired phone is marked as a phone candidate" \
  "$(jq -r '.devices[] | select(.mac == "AA:BB:CC:DD:EE:FF") | .phone' <<<"$candidates")" "true"

hotspot_setup
devices=$("$bin" devices --json)
ok "configured device JSON has expected fields" jq -e \
  'length == 1 and .[0].id == "bt-aabbccddeeff" and .[0].name == "Pixel 8" and .[0].kind == "phone" and .[0].transport == "bluetooth" and .[0].connected == false and .[0].rssi == null and .[0].presence == "unknown"' \
  <<<"$devices"
ok "devices JSON matches schema" schema_valid "$DELIGHT_TEST_REPO/schema/device.schema.json" <(printf '%s' "$devices")
export DELIGHT_SYSFS="$SANDBOX/no-adapter"
status=$("$bin" status --json)
is "configured status without adapter is unsupported" "$(jq -r .state <<<"$status")" "unsupported"
is "unsupported configured status offers connect" "$(jq -r '.actions[0].label' <<<"$status")" "Connect to phone hotspot"
export DELIGHT_SYSFS="$SANDBOX/sys"
is "configured doctor succeeds" "$(
  "$bin" doctor >/dev/null 2>&1
  echo $?
)" "0"
is "configured but disabled status is off" "$("$bin" status --json | jq -r .state)" "off"
is "disabled status keeps connect and settings actions" "$("$bin" status --json | jq '.actions | length')" "2"
hotspot_set enabled true
jq '.active = ["hotspot-uuid"]' "$DELIGHT_STUB_STATE/nm.json" >"$DELIGHT_STUB_STATE/nm.tmp"
mv "$DELIGHT_STUB_STATE/nm.tmp" "$DELIGHT_STUB_STATE/nm.json"
status=$("$bin" status --json)
is "active hotspot status is on" "$(jq -r .state <<<"$status")" "on"
is "active hotspot subtitle names phone" "$(jq -r .subtitle <<<"$status")" "Connected via Pixel 8"
is "active hotspot omits redundant connect action" "$(jq '.actions | length' <<<"$status")" "1"

done_testing
