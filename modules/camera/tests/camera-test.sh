#!/bin/bash

set -uo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"

sandbox
ROOT=$(repo_copy)
BIN="$ROOT/modules/camera/bin/delight-camera"
STUBS="$ROOT/modules/camera/tests/stubs"
export DELIGHT_SYSFS="$SANDBOX/sys"
export SYSFS="$DELIGHT_SYSFS"
export DELIGHT_CAMERA_MODULES_ROOT="$SANDBOX/modules"
export DELIGHT_CAMERA_SYSTEM_UNIT_DIR="$SANDBOX/system"
export WANT="$XDG_RUNTIME_DIR/omarchy-delight/camera-device/want"
export PATH="$STUBS:$PATH"
mkdir -p "$DELIGHT_SYSFS/module/v4l2loopback" "$DELIGHT_SYSFS/devices/virtual/video4linux/video10" \
  "$DELIGHT_CAMERA_MODULES_ROOT/6.x-omarchy" "$DELIGHT_CAMERA_SYSTEM_UNIT_DIR"
printf 'Cam Link 4K\n' >"$DELIGHT_SYSFS/devices/virtual/video4linux/video10/name"
printf 'linux-omarchy\n' >"$DELIGHT_CAMERA_MODULES_ROOT/6.x-omarchy/pkgbase"
touch "$DELIGHT_STUB_STATE/pkg-linux-omarchy"

status_json() {
  "$BIN" status --json
}

camera_schema_valid() {
  local schema="$1" data="$2"
  if python3 -c 'import jsonschema, referencing' >/dev/null 2>&1; then
    schema_valid "$schema" "$data"
  elif [[ ${schema##*/} == "device.schema.json" ]]; then
    jq -e 'type == "array" and all(.[]; type == "object" and (.id | type == "string" and length > 0) and (.name | type == "string") and (.kind == "phone" or .kind == "tablet" or .kind == "computer" or .kind == "headphones") and (.transport | type == "string" and length > 0) and (.connected | type == "boolean"))' "$data" >/dev/null
  else
    jq -e 'type == "object" and .schema == 1 and .id == "camera" and (.state == "on" or .state == "off" or .state == "busy" or .state == "needs-setup" or .state == "unsupported" or .state == "error") and (.title | type == "string") and (.subtitle | type == "string") and (.icon | type == "string") and (.toggle | type == "boolean") and (.actions | type == "array") and (.devices | type == "array") and (.reason == null or (.reason | type == "string")) and (.updated | type == "string")' "$data" >/dev/null
  fi
}

run_reconcile() {
  local line script
  line=$(sed -n 's/^ExecStart=//p' "$DELIGHT_CAMERA_SYSTEM_UNIT_DIR/delight-camera-loopback-$(id -u).service")
  script=${line#"/bin/sh -ec '"}
  script=${script%\'}
  script=${script//\$\$/\$}
  script=${script//%%/%}
  /bin/sh -ec "$script"
}

before_dry_hash=$(tree_hash "$HOME" "$XDG_RUNTIME_DIR")
ok "camera dry-run install" env DELIGHT_DRY_RUN=1 "$BIN" install
is "dry-run install leaves HOME and runtime untouched" "$(tree_hash "$HOME" "$XDG_RUNTIME_DIR")" "$before_dry_hash"
not_ok "dry-run install writes no privileged unit" test -e "$DELIGHT_CAMERA_SYSTEM_UNIT_DIR/delight-camera-loopback-$(id -u).service"

ok "camera install" "$BIN" install
header_line=$(grep -n '^omarchy-pkg-add linux-omarchy-headers$' "$DELIGHT_STUB_LOG" | head -n 1 | cut -d: -f1)
module_line=$(grep -n '^omarchy-pkg-add v4l2loopback-dkms$' "$DELIGHT_STUB_LOG" | head -n 1 | cut -d: -f1)
ok "kernel headers are installed before v4l2loopback" test "$header_line" -lt "$module_line"
not_ok "regular install never selects v4l2loopback-dc-dkms" grep -F v4l2loopback-dc-dkms "$DELIGHT_STUB_LOG"
ok "systemd 249 uses sudo install for both root units" test "$(grep -Fc 'sudo install -Dm644' "$DELIGHT_STUB_LOG")" -eq 2
not_ok "root units avoid unsupported systemctl edit stdin" grep -F "systemctl edit --stdin --force --full delight-camera-loopback-" "$DELIGHT_STUB_LOG"
ok "rendered helper uses devices=0" grep -F 'devices=0' "$DELIGHT_CAMERA_SYSTEM_UNIT_DIR/delight-camera-loopback-$(id -u).service"
ok "rendered helper disables start limit" grep -F 'StartLimitIntervalSec=0' "$DELIGHT_CAMERA_SYSTEM_UNIT_DIR/delight-camera-loopback-$(id -u).service"
not_ok "rendered units contain no global module edits or unloads" grep -Ei 'modprobe\.d|rmmod|modprobe -r' "$DELIGHT_CAMERA_SYSTEM_UNIT_DIR"/*
ok "no modprobe.d path appears in sandbox or command log" bash -c \
  '[[ -z $(find "$1" -path "*/modprobe.d/*" -type f -print -quit) ]] && ! grep -Fq modprobe.d "$2"' _ "$SANDBOX" "$DELIGHT_STUB_LOG"

ok "enable camera" "$BIN" enable
ok "test invokes rendered root reconcile script" run_reconcile
listing=$(v4l2loopback-ctl list 2>/dev/null)
ok "both named camera devices coexist" bash -c '[[ "$1" == *"Continuity Camera"* && "$1" == *"Cam Link 4K"* ]]' _ "$listing"
ok "Cam Link device remains unchanged" test "$(cat "$DELIGHT_SYSFS/devices/virtual/video4linux/video10/name")" != "Continuity Camera"
before_connect=$(status_json)
is "enabled camera without phone needs setup" "$(jq -r '.state + "|" + .subtitle' <<<"$before_connect")" "needs-setup|Connect your phone"
is "connect action is published" "$(jq -r '.actions[0].command | join(" ")' <<<"$before_connect")" "delight camera connect"

ok "connect over Wi-Fi" "$BIN" connect --wifi 192.168.1.20
device=$(jq -r '.device' "$XDG_RUNTIME_DIR/omarchy-delight/camera/connection.json")
is "Wi-Fi stream uses the requested IP and named device" "$(jq -r '[.backend,.transport,.ip,.port,.size,.device] | join("|")' "$XDG_RUNTIME_DIR/omarchy-delight/camera/connection.json")" "droidcam|wifi|192.168.1.20|4747|1280x720|$device"
ok "exercise DroidCam Wi-Fi stream arguments" "$BIN" _stream
ok "DroidCam receives no-controls and configured device" grep -F "droidcam-cli -nocontrols -dev=$device -size=1280x720 192.168.1.20 4747" "$DELIGHT_STUB_LOG"
wifi_status=$(status_json)
is "connected Wi-Fi status is on" "$(jq -r '.state + "|" + .subtitle' <<<"$wifi_status")" "on|Phone camera · 1280x720"
ok "connected status includes a phone device" jq -e '.devices[0].kind == "phone" and .devices[0].transport == "droidcam-wifi" and .devices[0].connected' <<<"$wifi_status"
devices_json="$SANDBOX/devices.json"
"$BIN" devices --json >"$devices_json"
ok "devices JSON matches device schema" camera_schema_valid "$DELIGHT_TEST_REPO/schema/device.schema.json" "$devices_json"
is "devices output equals status devices" "$("$BIN" devices --json)" "$(jq -c '.devices' <<<"$wifi_status")"

export DELIGHT_ADB_CONNECTED=1
ok "connect over USB with adb phone" "$BIN" connect --usb
ok "exercise DroidCam USB stream arguments" "$BIN" _stream
ok "USB Android uses adb transport" grep -F "droidcam-cli -nocontrols -dev=$device -size=1280x720 adb 4747" "$DELIGHT_STUB_LOG"
ok "doctor succeeds with a connected phone" "$BIN" doctor
export DELIGHT_CAMERA_CONNECT_WAIT=0.5 DELIGHT_STREAM_FAILS=1
not_ok "failed Wi-Fi connection exits with failure" "$BIN" connect --wifi 192.0.2.1
ok "connection failure notification is logged" grep -F "Continuity Camera connection failed" "$DELIGHT_STUB_LOG"
not_ok "failed connection removes connection file" test -e "$XDG_RUNTIME_DIR/omarchy-delight/camera/connection.json"
failed_status=$(status_json)
is "failed connection returns to needs setup" "$(jq -r '.state + "|" + .subtitle' <<<"$failed_status")" "needs-setup|Connect your phone"
unset DELIGHT_CAMERA_CONNECT_WAIT DELIGHT_STREAM_FAILS
not_ok "bad IPv4 is rejected" "$BIN" set ip 999.1.1.1
not_ok "bad port is rejected" "$BIN" set port 65536
not_ok "bad size is rejected" "$BIN" set size 1280by720

ok "disconnect camera stream" "$BIN" disconnect
not_ok "disconnect removes phone connection" test -e "$XDG_RUNTIME_DIR/omarchy-delight/camera/connection.json"
ok "disable camera" "$BIN" disable
ok "reconcile after disable" run_reconcile
listing=$(v4l2loopback-ctl list 2>/dev/null)
is "only Continuity Camera was deleted" "$(printf '%s\n' "$listing" | grep -Ec 'Continuity Camera|Cam Link 4K')" "1"
ok "Cam Link remains after disable" grep -F "Cam Link 4K" <<<"$listing"
ok "delete used only the Continuity Camera device path" grep -F "v4l2loopback-ctl delete /dev/video" "$DELIGHT_STUB_LOG"
not_ok "delete never targeted the Cam Link device" grep -F "v4l2loopback-ctl delete /dev/video10" "$DELIGHT_STUB_LOG"

rm -rf -- "$DELIGHT_SYSFS/module/v4l2loopback"
export DELIGHT_MODINFO_FAIL=1
unsupported=$(status_json)
is "unloadable module status is unsupported" "$(jq -r '.state' <<<"$unsupported")" "unsupported"
ok "unsupported status includes the kernel reason" jq -e '.reason | contains("v4l2loopback is not available for kernel")' <<<"$unsupported"
ok "unsupported status still exits zero" status_json
rm -f -- "$DELIGHT_STUB_STATE/pkg-linux-omarchy-headers"
doctor_output=$("$BIN" doctor 2>&1)
doctor_rc=$?
is "missing kernel headers are fixable" "$doctor_rc" "1"
ok "doctor names missing headers" grep -F 'fix headers: install linux-omarchy-headers' <<<"$doctor_output"
touch "$DELIGHT_STUB_STATE/pkg-linux-omarchy-headers"
doctor_output=$("$BIN" doctor 2>&1)
doctor_rc=$?
is "unbuilt module with headers is unsupported" "$doctor_rc" "2"
ok "doctor reports DKMS build failure" grep -F 'unsupported DKMS did not build v4l2loopback' <<<"$doctor_output"
mkdir -p "$DELIGHT_SYSFS/firmware/efi/efivars" "$DELIGHT_SYSFS/module/module/parameters"
printf '\0\0\0\0\1' >"$DELIGHT_SYSFS/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-e98c0b4185b4"
printf 'Y\n' >"$DELIGHT_SYSFS/module/module/parameters/sig_enforce"
doctor_output=$("$BIN" doctor 2>&1)
doctor_rc=$?
is "Secure Boot signed-module enforcement is unsupported" "$doctor_rc" "2"
ok "doctor explains Secure Boot enforcement" grep -F 'unsupported Secure Boot enforces signed modules' <<<"$doctor_output"

ok "enable camera before uninstall" "$BIN" enable
ok "reconcile camera before uninstall" run_reconcile
ok "camera uninstall" "$BIN" uninstall
uninstall_listing=$(v4l2loopback-ctl list 2>/dev/null)
not_ok "uninstall removes Continuity Camera" grep -F "Continuity Camera" <<<"$uninstall_listing"
ok "uninstall preserves Cam Link" grep -F "Cam Link 4K" <<<"$uninstall_listing"
not_ok "uninstall removes root service unit" test -e "$DELIGHT_CAMERA_SYSTEM_UNIT_DIR/delight-camera-loopback-$(id -u).service"
not_ok "uninstall removes root path unit" test -e "$DELIGHT_CAMERA_SYSTEM_UNIT_DIR/delight-camera-loopback-$(id -u).path"
not_ok "uninstall clears module state" test -e "$HOME/.local/state/omarchy-delight/camera"
is "uninstall clears camera config" "$(jq -r '.modules.camera // "none"' "$HOME/.config/omarchy-delight/config.json")" "none"
uninstalled_status="$SANDBOX/uninstalled-status.json"
status_json >"$uninstalled_status"
ok "status JSON remains valid after uninstall" camera_schema_valid "$DELIGHT_TEST_REPO/schema/status.schema.json" "$uninstalled_status"

done_testing
