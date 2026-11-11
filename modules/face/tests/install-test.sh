#!/bin/bash

# Install, on-demand units, Howdy Next fragment, and uninstall.
# Nothing here is a claim that the HM1092 streams.

# shellcheck source=../../../tests/lib/tap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"

MODULE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BIN=$MODULE/bin/delight-face
FIXTURES=$MODULE/tests/fixtures

sandbox
export PATH="$MODULE/tests/stubs:$PATH"
export DELIGHT_SYSFS=$SANDBOX/sys
export DELIGHT_FACE_SYSTEM_UNIT_DIR=$SANDBOX/system-units
export DELIGHT_FACE_UDEV_DIR=$SANDBOX/udev
export DELIGHT_FACE_TMPFILES_DIR=$SANDBOX/tmpfiles
export DELIGHT_FACE_MODULES_ROOT=$SANDBOX/kmod
export DELIGHT_FACE_DEV_ROOT=$SANDBOX/dev
export DELIGHT_FACE_SYSTEM_RUNTIME=$SANDBOX/run-system
export DELIGHT_FACE_DIRECT=1
mkdir -p -- "$DELIGHT_SYSFS/module/v4l2loopback" "$DELIGHT_FACE_MODULES_ROOT" \
  "$DELIGHT_SYSFS/devices/virtual/video4linux/video10"
printf '%s\n' "Cam Link 4K" >"$DELIGHT_SYSFS/devices/virtual/video4linux/video10/name"

before=$(tree_hash "$HOME" "$XDG_RUNTIME_DIR")
ok "dry-run install" env DELIGHT_DRY_RUN=1 "$BIN" install
is "dry-run leaves the sandbox untouched" "$(tree_hash "$HOME" "$XDG_RUNTIME_DIR")" "$before"
not_ok "dry-run writes no system unit" test -e "$DELIGHT_FACE_SYSTEM_UNIT_DIR/delight-face-bridge.socket"

ok "install" "$BIN" install
ok "install is idempotent" "$BIN" install
ok "install asks for libcamera" grep -F "omarchy-pkg-add libcamera" "$DELIGHT_STUB_LOG"
ok "install asks for the gstreamer IR source" grep -F "omarchy-pkg-add gst-plugin-libcamera" "$DELIGHT_STUB_LOG"
ok "install asks for v4l2loopback" grep -F "omarchy-pkg-add v4l2loopback-dkms" "$DELIGHT_STUB_LOG"
ok "install asks for the v4l2sink plugin" grep -F "omarchy-pkg-add gst-plugins-good" "$DELIGHT_STUB_LOG"
ok "install asks for nc so the socket client can connect" grep -F "omarchy-pkg-add openbsd-netcat" "$DELIGHT_STUB_LOG"
ok "install asks for howdy-next from the AUR" grep -F "omarchy-pkg-aur-add howdy-next" "$DELIGHT_STUB_LOG"
not_ok "install does not pull the UVC IR emitter tool" grep -F linux-enable-ir-emitter "$DELIGHT_STUB_LOG"
not_ok "install does not write PAM policy" grep -F "/etc/pam.d" "$DELIGHT_STUB_LOG"

fragment=$HOME/.config/omarchy-delight/face/howdy-next.ini
ok "howdy fragment is installed" test -f "$fragment"
ok "howdy fragment points at the loopback device" grep -F "device_path = /dev/v4l/by-id/delight-ir" "$fragment"
not_ok "howdy fragment is not a /dev/video index" grep -E '^device_path = /dev/video[0-9]+$' "$fragment"
ok "howdy fragment says the sensor is unverified" grep -F "unverified" "$fragment"

user_unit=$HOME/.config/systemd/user/delight-face.service
ok "user unit is installed" test -f "$user_unit"
ok "user unit arms the listener" grep -F "delight face _listen" "$user_unit"
not_ok "user unit does not start the bridge" grep -F "delight face bridge" "$user_unit"
ok "user unit is part of delight.target" grep -qx "PartOf=delight.target" "$user_unit"
ok "user unit is wanted by delight.target" grep -qx "WantedBy=delight.target" "$user_unit"

socket=$DELIGHT_FACE_SYSTEM_UNIT_DIR/delight-face-bridge.socket
service=$DELIGHT_FACE_SYSTEM_UNIT_DIR/delight-face-bridge@.service
ok "system socket is installed" test -f "$socket"
ok "socket accepts one capture at a time" grep -qx "Accept=yes" "$socket"
ok "socket listens without being a session camera" grep -qx "ListenStream=/run/omarchy-delight/face-bridge.sock" "$socket"
ok "socket is wanted by sockets.target" grep -qx "WantedBy=sockets.target" "$socket"
not_ok "socket is not wanted by the graphical session" grep -F "WantedBy=delight.target" "$socket"
ok "service template is installed" test -f "$service"
ok "service runs the bridge" grep -F "delight-face\" bridge" "$service"
ok "service reads the activating socket" grep -qx "StandardInput=socket" "$service"
ok "service cannot restart into a stuck stream" grep -qx "Restart=no" "$service"
ok "service has a hard stop so the privacy LED cannot stay on" grep -qx "RuntimeMaxSec=300" "$service"
not_ok "service is not enabled at boot" grep -F "WantedBy=" "$service"
not_ok "service template still contains the root placeholder" grep -F "@ROOT@" "$service"
ok "udev rule names only Delight IR" grep -F 'ATTR{name}=="Delight IR"' "$DELIGHT_FACE_UDEV_DIR/99-delight-ir.rules"
ok "udev rule creates the stable by-id link" grep -F 'SYMLINK+="v4l/by-id/delight-ir"' "$DELIGHT_FACE_UDEV_DIR/99-delight-ir.rules"
ok "tmpfiles creates the runtime directory" grep -F "/run/omarchy-delight" "$DELIGHT_FACE_TMPFILES_DIR/delight-face.conf"

is "installed status is off" "$("$BIN" status --json | jq -r .state)" "off"
ok "enable" "$BIN" enable
is "enabled status is on" "$("$BIN" status --json | jq -r .state)" "on"
is "enabled subtitle keeps the sensor off" "$("$BIN" status --json | jq -r .subtitle)" "Armed — sensor off until a capture"
not_ok "install did not enable the system socket" grep -F "systemctl enable --now delight-face-bridge.socket" "$DELIGHT_STUB_LOG"
ok "listen enables only the socket" "$BIN" _listen
ok "socket enable is recorded" grep -F "systemctl enable --now delight-face-bridge.socket" "$DELIGHT_STUB_LOG"
not_ok "listen does not start a bridge instance" grep -F "systemctl start delight-face-bridge@" "$DELIGHT_STUB_LOG"

rc=0
"$BIN" doctor >"$SANDBOX/doctor.out" 2>"$SANDBOX/doctor.err" || rc=$?
is "doctor reports missing packages as fixable" "$rc" "1"
ok "doctor names a missing package" grep -F "missing package: libcamera" "$SANDBOX/doctor.out"

while IFS= read -r pkg; do
  [[ -n $pkg ]] || continue
  touch -- "$DELIGHT_STUB_STATE/pkg-$pkg"
done < <(jq -r '.packages.repo[], .packages.aur[]' "$MODULE/module.json")

rc=0
DELIGHT_FACE_CAM_LIST=$FIXTURES/cam-list-rgb-only.txt "$BIN" doctor >"$SANDBOX/doctor.out" 2>"$SANDBOX/doctor.err" || rc=$?
is "doctor reports a missing IR stream as needing the user" "$rc" "3"
ok "doctor missing-stream text is explicit" grep -F "no IR camera stream:" "$SANDBOX/doctor.err"

rc=0
DELIGHT_FACE_CAM_LIST=$FIXTURES/cam-list-rgb-and-ir.txt "$BIN" doctor >"$SANDBOX/doctor.out" 2>"$SANDBOX/doctor.err" || rc=$?
is "doctor stays successful when hm1092 is only listed" "$rc" "0"
ok "listed sensor is still described as unverified" grep -F "Grey frames from the HM1092 are unverified" "$SANDBOX/doctor.out"
ok "doctor tells Howdy which device to use" grep -F "sudo howdy set device_path /dev/v4l/by-id/delight-ir" "$SANDBOX/doctor.out"
ok "doctor says PAM is untouched" grep -F "does not change PAM" "$SANDBOX/doctor.out"

script_out=$(DELIGHT_DRY_RUN=1 "$MODULE/scripts/install.sh" 2>&1)
ok "package install script lists howdy-next" grep -F howdy-next <<<"$script_out"
ok "package install script lists libcamera" grep -F libcamera <<<"$script_out"
ok "package install script dry-runs" grep -F "DRY:" <<<"$script_out"

ok "ensure creates the named loopback" "$BIN" ensure
ok "stable symlink was created under the test dev root" test -L "$DELIGHT_FACE_DEV_ROOT/v4l/by-id/delight-ir"
is "symlink targets the new loopback, not Cam Link" "$(readlink -- "$DELIGHT_FACE_DEV_ROOT/v4l/by-id/delight-ir")" "/dev/video11"
ok "Cam Link device is untouched" test -f "$DELIGHT_SYSFS/devices/virtual/video4linux/video10/name"

ok "uninstall script" "$MODULE/scripts/uninstall.sh"
not_ok "uninstall removes state" test -e "$HOME/.local/state/omarchy-delight/face"
not_ok "uninstall removes the howdy fragment" test -e "$fragment"
not_ok "uninstall removes the system socket" test -e "$socket"
not_ok "uninstall removes the system service" test -e "$service"
not_ok "uninstall removes the Delight IR device" test -e "$DELIGHT_SYSFS/devices/virtual/video4linux/video11"
ok "uninstall keeps Cam Link" test -f "$DELIGHT_SYSFS/devices/virtual/video4linux/video10/name"
not_ok "uninstall does not delete Cam Link" grep -F "v4l2loopback-ctl delete /dev/video10" "$DELIGHT_STUB_LOG"
ok "uninstall deletes Delight IR by path" grep -F "v4l2loopback-ctl delete /dev/video11" "$DELIGHT_STUB_LOG"
not_ok "uninstall does not unload v4l2loopback" grep -F "modprobe -r" "$DELIGHT_STUB_LOG"
ok "uninstall script is idempotent" "$MODULE/scripts/uninstall.sh"

rm -rf -- "$DELIGHT_SYSFS/module/v4l2loopback"
ok "reinstall without the kernel module" "$BIN" install
is "missing loopback is unsupported" "$("$BIN" status --json | jq -r .state)" "unsupported"
reason=$("$BIN" status --json | jq -r .reason)
ok "unsupported status explains why" grep -F "v4l2loopback is not available" <<<"$reason"
"$BIN" uninstall

done_testing
