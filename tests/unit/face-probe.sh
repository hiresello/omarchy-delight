#!/bin/bash

# Canned outputs for delight face probe. Fixtures are synthetic.
# They were not captured on an ASUS Zenbook A16.

# shellcheck source=../lib/tap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/tap.sh"

sandbox

PROBE="$DELIGHT_TEST_REPO/research/face/probe.sh"
DELIGHT="$DELIGHT_TEST_REPO/bin/delight"
FIX="$DELIGHT_TEST_REPO/research/face/fixtures"
export DELIGHT_FACE_PROBE_USER=juanprobe
export DELIGHT_FACE_PROBE_HOME=/home/juanprobe

assert_redacted() {
  local name="$1" file="$2"
  not_ok "$name hides colon mac" grep -E -q '([0-9a-f]{2}:){5}[0-9a-f]{2}' "$file"
  not_ok "$name hides dashed mac" grep -E -q '([0-9a-f]{2}-){5}[0-9a-f]{2}' "$file"
  not_ok "$name hides dotted mac" grep -E -q '([0-9a-f]{4}\.){2}[0-9a-f]{4}' "$file"
  not_ok "$name hides serial" grep -q 'ASUS123456789' "$file"
  not_ok "$name hides username" grep -q 'juanprobe' "$file"
  ok "$name marks mac" grep -q '\[mac\]' "$file"
  ok "$name marks serial" grep -q '\[serial\]' "$file"
  ok "$name marks user" grep -q '\[user\]' "$file"
}

run_fixture() {
  local name="$1" id="$2" phrase="$3" out stdout
  out="$SANDBOX/$name.txt"
  stdout=$("$PROBE" --fixture "$FIX/$name" --output "$out")
  is "$name verdict id" "$(grep -E '^Verdict id: ' "$out")" "Verdict id: $id"
  is "$name stdout id" "$(printf '%s\n' "$stdout" | head -n 1)" "Verdict id: $id"
  ok "$name phrase" grep -F -q "$phrase" <<<"$stdout"
  ok "$name report phrase" grep -F -q "$phrase" "$out"
  ok "$name names the report" grep -F -q "Wrote redacted report: $out" <<<"$stdout"
  is "$name source is the fixture" "$(grep -E '^source: ' "$out")" "source: fixture $name"
  ok "$name says fixture is not hardware evidence" grep -F -q "not hardware evidence" "$out"
  ok "$name says unverified" grep -F -q "Unverified" "$out"
  is "$name mode is user-only" "$(stat -c '%a' "$out")" "600"
  assert_redacted "$name" "$out"
}

run_fixture uvc-ir uvc-ir "The next path is Howdy Next."
ok "uvc fixture is not a mipi stack" grep -F -q "signals: uvc_ir=yes mipi=no rgb=no ir_node=no" "$SANDBOX/uvc-ir.txt"
not_ok "uvc fixture does not ask for kernel work" grep -F -q "Kernel and device-tree work is still needed" "$SANDBOX/uvc-ir.txt"

run_fixture mipi-rgb-only mipi-rgb-only "Kernel and device-tree work is still needed"
ok "rgb-only names ov02c10" grep -F -q "including the OV02C10 RGB sensor" "$SANDBOX/mipi-rgb-only.txt"
ok "rgb-only saw pm8010" grep -F -q "pm8010=yes" "$SANDBOX/mipi-rgb-only.txt"
not_ok "rgb-only is not the howdy path" grep -F -q "The next path is Howdy Next." "$SANDBOX/mipi-rgb-only.txt"
not_ok "rgb-only is not an illuminator verdict" grep -F -q "illuminator or driver issue" "$SANDBOX/mipi-rgb-only.txt"

run_fixture mipi-rgb-ir mipi-ir-no-stream "illuminator or driver issue"
ok "rgb-ir keeps the sensor name in the log" grep -F -q "hm1092" "$SANDBOX/mipi-rgb-ir.txt"
ok "rgb-ir has no userspace ir stream" grep -F -q "ir_stream=no" "$SANDBOX/mipi-rgb-ir.txt"
not_ok "rgb-ir is not the howdy path" grep -F -q "The next path is Howdy Next." "$SANDBOX/mipi-rgb-ir.txt"

run_fixture nothing nothing "not proof that the sensors are missing"
ok "nothing mentions the blacklist" grep -F -q "blacklists camera-related modules (i2c_qcom_cci,qcom_camss,ov02c10)" "$SANDBOX/nothing.txt"
ok "nothing redacts the disk uuid" grep -F -q "UUID=[uuid]" "$SANDBOX/nothing.txt"
not_ok "nothing hides the disk uuid" grep -F -q "12345678-1234-1234-1234-123456789abc" "$SANDBOX/nothing.txt"
ok "nothing keeps mipi unset despite blacklist names" grep -F -q "mipi=no" "$SANDBOX/nothing.txt"
ok "privacy led alone is not a camera stack" grep -F -q "privacy-led" "$SANDBOX/nothing.txt"
not_ok "nothing is not kernel-work-for-ir" grep -F -q "Kernel and device-tree work is still needed" "$SANDBOX/nothing.txt"

# IR node plus a listed capture mode is not the illuminator branch.
stream="$SANDBOX/ir-stream"
mkdir -p "$stream"
cp -a "$FIX/mipi-rgb-ir/." "$stream/"
cat >"$stream/cam.txt" <<'EOF'
Available cameras:
1: 'ov02c10' (ov02c10)
    Modes: 'SBGGR10_CSI2P' : 1280x720 [30.00 fps]
2: 'hm1092' (hm1092)
    Modes: 'R10_CSI2P' : 560x360 [30.00 fps]
EOF
stream_out=$("$PROBE" --fixture "$stream" --output "$SANDBOX/ir-stream.txt")
is "listed ir capture verdict" "$(head -n 1 <<<"$stream_out")" "Verdict id: ir-capture-listed"
ok "listed ir capture stays off howdy" grep -F -q "Stay off the Howdy Next path" <<<"$stream_out"
not_ok "listed ir capture is not the illuminator branch" grep -F -q "illuminator or driver issue" <<<"$stream_out"

# A USB name that looks infrared, with uvcvideo absent, is not Howdy Next.
usb="$SANDBOX/usb-named"
mkdir -p "$usb"
cp -a "$FIX/nothing/." "$usb/"
printf '%s\n' "quiet rw" >"$usb/cmdline.txt"
cat >"$usb/lsusb.txt" <<'EOF'
Bus 002 Device 003: ID 1234:5678 Example Vendor HM1092
probe-canary user=juanprobe SerialNumber: ASUS123456789 mac aa:bb:cc:dd:ee:ff dotted aabb.ccdd.eeff dashed aa-bb-cc-dd-ee-ff
EOF
usb_out=$("$PROBE" --fixture "$usb" --output "$SANDBOX/usb-named.txt")
is "unbound usb ir verdict" "$(head -n 1 <<<"$usb_out")" "Verdict id: usb-ir-not-uvc"
ok "unbound usb ir says uvcvideo is not bound" grep -F -q "uvcvideo is not bound" <<<"$usb_out"
assert_redacted "unbound usb ir" "$SANDBOX/usb-named.txt"

# Unreadable kernel log and no other camera evidence is not "nothing".
blind="$SANDBOX/blind"
mkdir -p "$blind"
cp -a "$FIX/nothing/." "$blind/"
printf '%s\n' "quiet rw" >"$blind/cmdline.txt"
printf '%s\n' "(unreadable: Operation not permitted)" >"$blind/dmesg.txt"
blind_out=$("$PROBE" --fixture "$blind" --output "$SANDBOX/blind.txt")
is "unreadable dmesg verdict" "$(head -n 1 <<<"$blind_out")" "Verdict id: incomplete"
ok "unreadable dmesg does not claim the sensor is missing" grep -F -q "could not see enough" <<<"$blind_out"

# pm8010 alone is not a MIPI camera stack.
rail="$SANDBOX/rail"
mkdir -p "$rail"
cp -a "$FIX/nothing/." "$rail/"
printf '%s\n' "quiet rw" >"$rail/cmdline.txt"
printf '%s\n' "pm8010 3-0010: regulators ready" >"$rail/dmesg.txt"
rail_out=$("$PROBE" --fixture "$rail" --output "$SANDBOX/rail.txt")
is "pm8010 alone verdict" "$(head -n 1 <<<"$rail_out")" "Verdict id: nothing"
ok "pm8010 alone is called out" grep -F -q "mentions pm8010" <<<"$rail_out"

# A username that is also a hardware word stays in /dev/video0.
video_fix="$SANDBOX/video-user"
mkdir -p "$video_fix"
cp -a "$FIX/uvc-ir/." "$video_fix/"
printf '%s\n' "path /home/video/secret and node /dev/video0" >>"$video_fix/lsusb.txt"
video_out_file="$SANDBOX/video-user.txt"
DELIGHT_FACE_PROBE_USER=video DELIGHT_FACE_PROBE_HOME=/home/video \
  "$PROBE" --fixture "$video_fix" --output "$video_out_file" >/dev/null
not_ok "hardware-word username stays in video node" grep -q '/dev/\[user\]0' "$video_out_file"
ok "video node survives redaction" grep -q '/dev/video0' "$video_out_file"
not_ok "home directory is scrubbed" grep -q '/home/video' "$video_out_file"
ok "home marker present" grep -q '\[home\]' "$video_out_file"

mkdir -p "$SANDBOX/wd"
(
  cd "$SANDBOX/wd" || exit 1
  "$PROBE" --fixture "$FIX/nothing" >/dev/null
)
ok "default report path" test -f "$SANDBOX/wd/delight-face-probe.txt"

ok "probe help" "$PROBE" --help
face_help=$("$DELIGHT" face --help)
face_help_rc=$?
ok "delight face help" test "$face_help_rc" -eq 0
ok "delight face help names the probe" grep -F -q "probe" <<<"$face_help"
ok "delight face help names the module" grep -F -q "install" <<<"$face_help"
from_cli=$("$DELIGHT" face probe --fixture "$FIX/uvc-ir" --output "$SANDBOX/from-delight.txt")
is "dispatcher verdict" "$(head -n 1 <<<"$from_cli")" "Verdict id: uvc-ir"
not_ok "unknown face command fails" "$DELIGHT" face enroll
not_ok "missing fixture fails" "$PROBE" --fixture "$SANDBOX/no-such-fixture" --output "$SANDBOX/missing.txt"

# Live collection against a fake /proc, /sys, and /dev. Not an A16.
live="$SANDBOX/live"
mkdir -p \
  "$live/bin" \
  "$live/proc/device-tree/serial-number" \
  "$live/proc/device-tree/soc/camss@ac01000" \
  "$live/sys/bus/usb/drivers/uvcvideo/1-5:1.0" \
  "$live/sys/bus/usb/drivers/uvcvideo/bind" \
  "$live/sys/class/leds/privacy-led" \
  "$live/dev"
printf 'ASUSTeK COMPUTER INC. ASUS Zenbook UX3607OA\0' >"$live/proc/device-tree/model"
printf 'SECRETSERIAL\0' >"$live/proc/device-tree/serial-number/raw"
printf 'qcom,camss\0' >"$live/proc/device-tree/soc/camss@ac01000/compatible"
printf '%s\n' "quiet rw" >"$live/proc/cmdline"
: >"$live/dev/media0"
: >"$live/dev/media1"
cat >"$live/bin/uname" <<'EOF'
#!/bin/bash
echo 9.9.9-test
EOF
cat >"$live/bin/lsusb" <<'EOF'
#!/bin/bash
echo "Bus 002 Device 004: ID 1234:5678 Example Vendor Integrated IR Camera"
EOF
cat >"$live/bin/v4l2-ctl" <<'EOF'
#!/bin/bash
[[ $* == *--list-devices* ]] || exit 1
printf '%s\n' "Integrated IR Camera (usb-0000:00:14.0-5):" $'\t/dev/video0'
EOF
cat >"$live/bin/media-ctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"${LIVE_MEDIA_LOG:?}"
printf '%s\n' "driver          uvcvideo" "model           Integrated IR Camera" "bus info        usb-x"
EOF
cat >"$live/bin/dmesg" <<'EOF'
#!/bin/bash
printf '%s\n' "bluetooth: idle" "ov02c10 1-0036: probed SerialNumber: ASUS123456789"
EOF
cat >"$live/bin/cam" <<'EOF'
#!/bin/bash
[[ $* == *-l* ]] || exit 1
printf '%s\n' "No cameras available."
EOF
chmod +x "$live/bin/"*
export LIVE_MEDIA_LOG="$live/media.log"
: >"$LIVE_MEDIA_LOG"
live_stdout=$(
  PATH="$live/bin:$PATH" \
    DELIGHT_FACE_PROBE_PROC="$live/proc" \
    DELIGHT_FACE_PROBE_SYS="$live/sys" \
    DELIGHT_FACE_PROBE_DEV="$live/dev" \
    "$PROBE" --output "$live/report.txt"
)
ok "live report exists" test -s "$live/report.txt"
is "live stub verdict" "$(head -n 1 <<<"$live_stdout")" "Verdict id: uvc-ir"
ok "live stub says it is live" grep -F -q "source: live" "$live/report.txt"
ok "live stub keeps camss node" grep -F -q "qcom,camss" "$live/report.txt"
not_ok "live stub drops serial-number node" grep -F -q "SECRETSERIAL" "$live/report.txt"
not_ok "live stub filters unrelated dmesg" grep -F -q "bluetooth" "$live/report.txt"
ok "live stub keeps ov02c10 dmesg line" grep -F -q "ov02c10" "$live/report.txt"
not_ok "live stub redacts dmesg serial" grep -F -q "ASUS123456789" "$live/report.txt"
ok "live stub redacts serial marker" grep -F -q "[serial]" "$live/report.txt"
ok "live stub lists both media nodes" grep -F -q -- "-d $live/dev/media0 -p" "$LIVE_MEDIA_LOG"
ok "live stub lists second media node" grep -F -q -- "-d $live/dev/media1 -p" "$LIVE_MEDIA_LOG"
ok "live stub records uvcvideo interface" grep -F -q "1-5:1.0" "$live/report.txt"
ok "live stub records privacy led" grep -F -q "privacy-led" "$live/report.txt"
ok "live stub kernel version" grep -F -q "kernel: 9.9.9-test" "$live/report.txt"
not_ok "live mipi fact does not override uvc verdict" grep -F -q "Verdict id: mipi-rgb-only" "$live/report.txt"

done_testing
