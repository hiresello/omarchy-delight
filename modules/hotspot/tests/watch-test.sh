#!/bin/bash

source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/test-lib"

hotspot_test_init
hotspot_nm_fixture
hotspot_bt_fixture
bin="$DELIGHT_TEST_REPO/modules/hotspot/bin/delight-hotspot"
hotspot_log_count() {
  local count
  count=$(grep -cE "$1" "$DELIGHT_STUB_LOG" || true)
  [[ $count == 0 ]] || printf '%s' "$count"
}
hotspot_setup
"$bin" enable
hotspot_set proximity.nearDwell 0
hotspot_set proximity.awayDwell 20
hotspot_set proximity.smoothing 1
hotspot_set scan.window 1
hotspot_set backoff.max 60

hotspot_run_watch 1000
is "near phone autojoins the configured hotspot" \
  "$(jq -r '.active[0]' "$DELIGHT_STUB_STATE/nm.json")" "hotspot-uuid"
is "successful autojoin resets backoff" \
  "$(jq -r '.attempts' "$XDG_RUNTIME_DIR/omarchy-delight/hotspot/autojoin.json")" "0"

jq '.active = [] | .upFail = 4' "$DELIGHT_STUB_STATE/nm.json" >"$DELIGHT_STUB_STATE/nm.tmp"
mv "$DELIGHT_STUB_STATE/nm.tmp" "$DELIGHT_STUB_STATE/nm.json"
hotspot_bt_fixture
hotspot_run_watch 1100
is "first failed autojoin uses initial backoff" \
  "$(jq -c '[.attempts,.backoff,.nextAttempt]' "$XDG_RUNTIME_DIR/omarchy-delight/hotspot/autojoin.json")" \
  '[1,15,1115]'
: >"$DELIGHT_STUB_LOG"
hotspot_bt_fixture
hotspot_run_watch 1114
is "backoff suppresses premature retry" \
  "$(hotspot_log_count '^nmcli connection up uuid hotspot-uuid$')" ""
hotspot_bt_fixture
hotspot_run_watch 1115
is "second failure doubles backoff" \
  "$(jq -c '[.attempts,.backoff,.nextAttempt]' "$XDG_RUNTIME_DIR/omarchy-delight/hotspot/autojoin.json")" \
  '[2,30,1145]'
hotspot_bt_fixture
hotspot_run_watch 1145
is "third failure doubles backoff to 60 seconds" \
  "$(jq -c '[.attempts,.backoff,.nextAttempt]' "$XDG_RUNTIME_DIR/omarchy-delight/hotspot/autojoin.json")" \
  '[3,60,1205]'
hotspot_bt_fixture
hotspot_run_watch 1205
is "backoff is capped at configured maximum" \
  "$(jq -c '[.attempts,.backoff,.nextAttempt]' "$XDG_RUNTIME_DIR/omarchy-delight/hotspot/autojoin.json")" \
  '[4,60,1265]'

jq '.active = ["hotspot-uuid"]' "$DELIGHT_STUB_STATE/nm.json" >"$DELIGHT_STUB_STATE/nm.tmp"
mv "$DELIGHT_STUB_STATE/nm.tmp" "$DELIGHT_STUB_STATE/nm.json"
hotspot_bt_fixture
hotspot_run_watch 1300
is "online profile resets retry state" \
  "$(jq -c '[.attempts,.backoff,.nextAttempt]' "$XDG_RUNTIME_DIR/omarchy-delight/hotspot/autojoin.json")" \
  '[0,0,0]'

jq '.active = [] | .devices = [{type:"wifi",state:"connected"}] | .upFail = 1' \
  "$DELIGHT_STUB_STATE/nm.json" >"$DELIGHT_STUB_STATE/nm.tmp"
mv "$DELIGHT_STUB_STATE/nm.tmp" "$DELIGHT_STUB_STATE/nm.json"
hotspot_bt_fixture
hotspot_run_watch 1310
is "other online Wi-Fi connection prevents hotspot join" \
  "$(jq -r '.upFail' "$DELIGHT_STUB_STATE/nm.json")" "1"
is "online Wi-Fi resets retry state" \
  "$(jq -c '[.attempts,.backoff,.nextAttempt]' "$XDG_RUNTIME_DIR/omarchy-delight/hotspot/autojoin.json")" \
  '[0,0,0]'

jq '.active = [] | .devices = [{type:"wifi",state:"disconnected"}]' \
  "$DELIGHT_STUB_STATE/nm.json" >"$DELIGHT_STUB_STATE/nm.tmp"
mv "$DELIGHT_STUB_STATE/nm.tmp" "$DELIGHT_STUB_STATE/nm.json"
hotspot_set autoJoin false
: >"$DELIGHT_STUB_LOG"
hotspot_bt_fixture
hotspot_run_watch 2000
jq '.devices["AA:BB:CC:DD:EE:FF"].rssi = [-90]' "$DELIGHT_STUB_STATE/bt.json" >"$DELIGHT_STUB_STATE/bt.tmp"
mv "$DELIGHT_STUB_STATE/bt.tmp" "$DELIGHT_STUB_STATE/bt.json"
hotspot_run_watch 2010
is "away hint waits for away dwell" \
  "$(jq -r '.presence' "$XDG_RUNTIME_DIR/omarchy-delight/hotspot/proximity.json")" "near"
jq '.devices["AA:BB:CC:DD:EE:FF"].rssi = [-90]' "$DELIGHT_STUB_STATE/bt.json" >"$DELIGHT_STUB_STATE/bt.tmp"
mv "$DELIGHT_STUB_STATE/bt.tmp" "$DELIGHT_STUB_STATE/bt.json"
hotspot_run_watch 2030
is "away dwell eventually transitions" \
  "$(jq -r '.presence' "$XDG_RUNTIME_DIR/omarchy-delight/hotspot/proximity.json")" "away"
is "default hints do not send notifications" \
  "$(hotspot_log_count '^omarchy-notification-send ')" ""
is "default hints do not lock the session" \
  "$(hotspot_log_count '^omarchy-system-lock$')" ""
is "disabled autojoin does not bring up a profile" \
  "$(jq -r '.active | length' "$DELIGHT_STUB_STATE/nm.json")" "0"
hotspot_set autoJoin true
: >"$DELIGHT_STUB_LOG"
jq '.devices["AA:BB:CC:DD:EE:FF"].rssi = [-90]' "$DELIGHT_STUB_STATE/bt.json" >"$DELIGHT_STUB_STATE/bt.tmp"
mv "$DELIGHT_STUB_STATE/bt.tmp" "$DELIGHT_STUB_STATE/bt.json"
hotspot_run_watch 2035
is "away phone does not autojoin while autoJoin is enabled" \
  "$(hotspot_log_count '^nmcli connection up uuid hotspot-uuid$')" ""
hotspot_set autoJoin false

hotspot_set hints.away lock
hotspot_set hints.return wake
jq '.devices["AA:BB:CC:DD:EE:FF"].rssi = [-55]' "$DELIGHT_STUB_STATE/bt.json" >"$DELIGHT_STUB_STATE/bt.tmp"
mv "$DELIGHT_STUB_STATE/bt.tmp" "$DELIGHT_STUB_STATE/bt.json"
hotspot_run_watch 2040
ok "return wake hint turns display on" grep -Fq 'omarchy-brightness-display on' "$DELIGHT_STUB_LOG"

jq '.devices["AA:BB:CC:DD:EE:FF"].rssi = [-90]' "$DELIGHT_STUB_STATE/bt.json" >"$DELIGHT_STUB_STATE/bt.tmp"
mv "$DELIGHT_STUB_STATE/bt.tmp" "$DELIGHT_STUB_STATE/bt.json"
hotspot_run_watch 2050
jq '.devices["AA:BB:CC:DD:EE:FF"].rssi = [-90]' "$DELIGHT_STUB_STATE/bt.json" >"$DELIGHT_STUB_STATE/bt.tmp"
mv "$DELIGHT_STUB_STATE/bt.tmp" "$DELIGHT_STUB_STATE/bt.json"
hotspot_run_watch 2070
is "lock hint invokes lock wrapper once" \
  "$(hotspot_log_count '^omarchy-system-lock$')" "1"
jq '.devices["AA:BB:CC:DD:EE:FF"].rssi = [-90]' "$DELIGHT_STUB_STATE/bt.json" >"$DELIGHT_STUB_STATE/bt.tmp"
mv "$DELIGHT_STUB_STATE/bt.tmp" "$DELIGHT_STUB_STATE/bt.json"
hotspot_run_watch 2080
is "continued away state does not lock again" \
  "$(hotspot_log_count '^omarchy-system-lock$')" "1"

jq '.devices["AA:BB:CC:DD:EE:FF"].rssi = [-55]' "$DELIGHT_STUB_STATE/bt.json" >"$DELIGHT_STUB_STATE/bt.tmp"
mv "$DELIGHT_STUB_STATE/bt.tmp" "$DELIGHT_STUB_STATE/bt.json"
hotspot_run_watch 2090
export DELIGHT_STUB_LOCKED=0
jq '.devices["AA:BB:CC:DD:EE:FF"].rssi = [-90]' "$DELIGHT_STUB_STATE/bt.json" >"$DELIGHT_STUB_STATE/bt.tmp"
mv "$DELIGHT_STUB_STATE/bt.tmp" "$DELIGHT_STUB_STATE/bt.json"
jq '.devices["AA:BB:CC:DD:EE:FF"].rssi = [-90]' "$DELIGHT_STUB_STATE/bt.json" >"$DELIGHT_STUB_STATE/bt.tmp"
mv "$DELIGHT_STUB_STATE/bt.tmp" "$DELIGHT_STUB_STATE/bt.json"
hotspot_run_watch 2100
jq '.devices["AA:BB:CC:DD:EE:FF"].rssi = [-90]' "$DELIGHT_STUB_STATE/bt.json" >"$DELIGHT_STUB_STATE/bt.tmp"
mv "$DELIGHT_STUB_STATE/bt.tmp" "$DELIGHT_STUB_STATE/bt.json"
hotspot_run_watch 2120
is "locked session skips automatic locking" \
  "$(hotspot_log_count '^omarchy-system-lock$')" "1"
unset DELIGHT_STUB_LOCKED

hotspot_set hints.away notify
jq '.devices["AA:BB:CC:DD:EE:FF"].rssi = [-55]' "$DELIGHT_STUB_STATE/bt.json" >"$DELIGHT_STUB_STATE/bt.tmp"
mv "$DELIGHT_STUB_STATE/bt.tmp" "$DELIGHT_STUB_STATE/bt.json"
hotspot_run_watch 2130
jq '.devices["AA:BB:CC:DD:EE:FF"].rssi = [-90]' "$DELIGHT_STUB_STATE/bt.json" >"$DELIGHT_STUB_STATE/bt.tmp"
mv "$DELIGHT_STUB_STATE/bt.tmp" "$DELIGHT_STUB_STATE/bt.json"
hotspot_run_watch 2140
jq '.devices["AA:BB:CC:DD:EE:FF"].rssi = [-90]' "$DELIGHT_STUB_STATE/bt.json" >"$DELIGHT_STUB_STATE/bt.tmp"
mv "$DELIGHT_STUB_STATE/bt.tmp" "$DELIGHT_STUB_STATE/bt.json"
hotspot_run_watch 2160
ok "notify hint offers lock-now action" grep -Fq -- '--exec delight hotspot lock-now' "$DELIGHT_STUB_LOG"
"$bin" lock-now
is "lock-now action invokes lock wrapper" \
  "$(hotspot_log_count '^omarchy-system-lock$')" "2"

hotspot_set proximity.method connect
hotspot_run_watch 2200
ok "connect proximity mode attempts a Bluetooth connection" \
  grep -Fq 'bluetoothctl connect AA:BB:CC:DD:EE:FF' "$DELIGHT_STUB_LOG"
dry=$(DELIGHT_DRY_RUN=1 DELIGHT_HOTSPOT_NOW=2201 "$bin" watch --once 2>&1)
ok "dry-run prints the Bluetooth connection attempt" \
  grep -Fq 'DRY: timeout 10 bluetoothctl connect AA:BB:CC:DD:EE:FF' <<<"$dry"
is "dry-run does not connect Bluetooth" \
  "$(hotspot_log_count '^bluetoothctl connect AA:BB:CC:DD:EE:FF$')" "1"
hotspot_set proximity.method scan

mkdir -p "$DELIGHT_SYSFS/class/power_supply/BAT0"
printf 'Battery\n' >"$DELIGHT_SYSFS/class/power_supply/BAT0/type"
printf '1\n' >"$DELIGHT_SYSFS/class/power_supply/BAT0/present"
printf 'System\n' >"$DELIGHT_SYSFS/class/power_supply/BAT0/scope"
printf 'Discharging\n' >"$DELIGHT_SYSFS/class/power_supply/BAT0/status"
printf '15\n' >"$DELIGHT_SYSFS/class/power_supply/BAT0/capacity"
scans_before=$(hotspot_log_count '^bluetoothctl --timeout 1 scan on$')
hotspot_run_watch 3000
is "low battery pauses watcher" "$(jq -r '.presence' "$XDG_RUNTIME_DIR/omarchy-delight/hotspot/proximity.json")" "paused"
status=$("$bin" status --json)
is "paused status subtitle shows battery threshold" "$(jq -r .subtitle <<<"$status")" "Paused: battery below 20%"
scans_after=$(hotspot_log_count '^bluetoothctl --timeout 1 scan on$')
is "low battery avoids Bluetooth scans" "$scans_after" "$scans_before"

printf '25\n' >"$DELIGHT_SYSFS/class/power_supply/BAT0/capacity"
hotspot_run_watch 3001
not_ok "battery recovery resumes presence sampling" test \
  "$(jq -r '.presence' "$XDG_RUNTIME_DIR/omarchy-delight/hotspot/proximity.json")" = paused
printf '15\n' >"$DELIGHT_SYSFS/class/power_supply/BAT0/capacity"
hotspot_run_watch 3002
is "low battery pauses again before AC power" \
  "$(jq -r '.presence' "$XDG_RUNTIME_DIR/omarchy-delight/hotspot/proximity.json")" "paused"

mkdir -p "$DELIGHT_SYSFS/class/power_supply/AC"
printf 'Mains\n' >"$DELIGHT_SYSFS/class/power_supply/AC/type"
printf '1\n' >"$DELIGHT_SYSFS/class/power_supply/AC/online"
hotspot_run_watch 3003
not_ok "AC power resumes presence sampling" test \
  "$(jq -r '.presence' "$XDG_RUNTIME_DIR/omarchy-delight/hotspot/proximity.json")" = paused

export DELIGHT_SYSFS="$SANDBOX/no-adapter"
hotspot_run_watch 3100
is "watcher reports unknown without adapter" \
  "$(jq -r '.presence' "$XDG_RUNTIME_DIR/omarchy-delight/hotspot/proximity.json")" "unknown"
not_ok "module has no unlock path" \
  grep -rEn 'unlock-session|lock unlock|unlock' "$DELIGHT_TEST_REPO/modules/hotspot/bin" "$DELIGHT_TEST_REPO/modules/hotspot/lib"

done_testing
