#!/bin/bash

# shellcheck source=../../../tests/lib/tap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"

sandbox
ROOT="$DELIGHT_TEST_REPO"
BIN="$ROOT/modules/phone/bin/delight-phone"
SCHEMA="$ROOT/schema"
FIXTURE="$ROOT/modules/phone/tests/fixtures/delightd.json"
export DELIGHT_PHONE_FIXTURE="$FIXTURE"
export DELIGHT_SYSFS="$SANDBOX/sys"
mkdir -p "$DELIGHT_SYSFS/class/bluetooth/hci0"
STUB_DAEMON="$ROOT/modules/phone/tests/stubs/delightd"
export DELIGHT_DELIGHTD_SOURCE="$STUB_DAEMON"
touch "$DELIGHT_STUB_STATE/pkg-bluez"
STATUS_FILE="$XDG_RUNTIME_DIR/omarchy-delight/delightd.json"
DAEMON="$HOME/.local/lib/omarchy-delight/delightd"

state() {
  "$BIN" status --json | jq -r "$1"
}

is "before install: needs-setup" "$(state .state)" "needs-setup"
ok "install" "$BIN" install
ok "install copies delightd" test -x "$DAEMON"
ok "install pulls no KDE Connect or phone-app packages" tap_not grep -Eq "kdeconnect|localsend" "$DELIGHT_STUB_LOG"
is "installed, disabled: off" "$(state .state)" "off"
ok "enable" "$BIN" enable
ok "enable starts delightd's unit" grep -F "enable --now delight-phone.service" "$DELIGHT_STUB_LOG"
is "enabled before delightd reports: Starting" "$(state .subtitle)" "Starting…"

mkdir -p "${STATUS_FILE%/*}"
cp "$FIXTURE" "$STATUS_FILE"
status=$("$BIN" status --json)
ok "status validates" schema_valid "$SCHEMA/status.schema.json" <(printf '%s\n' "$status")
is "now playing is the subtitle" "$(jq -r .subtitle <<<"$status")" "▶ Midnight City · M83"
ok "media actions offered while playing" jq -e 'any(.actions[]; .label == "Play/Pause")' <<<"$status"
devices=$("$BIN" devices --json)
ok "devices validate" schema_valid "$SCHEMA/device.schema.json" <(printf '%s\n' "$devices")
is "only paired iPhones are devices" "$(jq -c 'map([.name,.transport,.connected])' <<<"$devices")" '[["Juan'"'"'s iPhone","ble",true]]'

jq '.nowPlaying = null' "$FIXTURE" >"$STATUS_FILE"
is "connected, nothing playing" "$(state .subtitle)" "Juan's iPhone · connected"
jq '.phones = [] | .nowPlaying = null' "$FIXTURE" >"$STATUS_FILE"
is "no phone paired" "$(state .subtitle)" "No iPhone paired"
ok "doctor asks the user to pair" bash -c '"$1" doctor; test $? -eq 3' _ "$BIN"
jq '.pairing = true' "$FIXTURE" >"$STATUS_FILE"
ok "pairing subtitle tells the user where to tap" jq -e '.subtitle | startswith("Pairing")' <<<"$("$BIN" status --json)"
jq '.error = "cannot advertise: Not Supported"' "$FIXTURE" >"$STATUS_FILE"
is "daemon error surfaces as error" "$(state .state)" "error"
is "error reason is the daemon's" "$(state .reason)" "cannot advertise: Not Supported"
cp "$FIXTURE" "$STATUS_FILE"

export DELIGHT_DELIGHTD="$STUB_DAEMON"
: >"$DELIGHT_STUB_LOG"
ok "pair opens the pairing window" "$BIN" pair
ok "pair asks delightd" grep -Fx "delightd pair" "$DELIGHT_STUB_LOG"
ok "pair tells the user what to tap" grep -F "Settings › Bluetooth" "$DELIGHT_STUB_LOG"
ok "media toggle" "$BIN" media toggle
ok "media goes to delightd" grep -Fx "delightd media toggle" "$DELIGHT_STUB_LOG"
not_ok "unknown media command fails" "$BIN" media eject
not_ok "media fails without a connected iPhone" env DELIGHT_PHONE_NO_MEDIA=true "$BIN" media next
unset DELIGHT_DELIGHTD

mv "$DAEMON" "$DAEMON.off"
not_ok "enable refuses without delightd" "$BIN" enable
mv "$DAEMON.off" "$DAEMON"
ok "publish rewrites the Control Center status" bash -c '"$1" publish && test -s "$2"' _ "$BIN" "$XDG_RUNTIME_DIR/omarchy-delight/status/phone.json"
ok "delightd changes trigger a republish" grep -Fx "PathChanged=%t/omarchy-delight/delightd.json" "$ROOT/modules/phone/systemd/delight-phone-status.path"

rm -rf "$DELIGHT_SYSFS/class/bluetooth/hci0"
is "no Bluetooth adapter: unsupported" "$(state .state)" "unsupported"
ok "doctor reports unsupported" bash -c '"$1" doctor; test $? -eq 2' _ "$BIN"
mkdir -p "$DELIGHT_SYSFS/class/bluetooth/hci0"

ok "uninstall" "$BIN" uninstall
not_ok "uninstall removes delightd" test -e "$DAEMON"

done_testing
