#!/bin/bash

# The capture graph is exercised with videotestsrc. That is not an HM1092.

# shellcheck source=../../../tests/lib/tap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"

MODULE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BIN=$MODULE/bin/delight-face
FIXTURES=$MODULE/tests/fixtures
STUB=$MODULE/tests/stubs/gst-launch-1.0

sandbox

unset DELIGHT_FACE_GST DELIGHT_FACE_STUB_SLEEP DELIGHT_FACE_SOURCE DELIGHT_FACE_SINK

if ! command -v gst-launch-1.0 >/dev/null 2>&1; then
  echo "not ok 1 - gst-launch-1.0 is required to test the grey pipeline"
  echo "1..1"
  exit 1
fi

rc=0
sample=$("$BIN" self-test 2>"$SANDBOX/self.err") || rc=$?
is "self-test exits 0" "$rc" "0"
ok "self-test reports a GRAY8 videotestsrc sample" grep -F "grey-sample ok bytes=256 format=GRAY8 source=videotestsrc" <<<"$sample"
ok "self-test says the HM1092 is unverified" grep -F "Real HM1092 output is unverified" <<<"$sample"
not_ok "self-test does not claim the sensor works" grep -F "HM1092 works" <<<"$sample"
not_ok "self-test does not claim A16 verification" grep -F "verified on the A16" <<<"$sample"

export DELIGHT_FACE_DIRECT=1
export DELIGHT_FACE_SOURCE=libcamera
export DELIGHT_FACE_SINK=fakesink
export DELIGHT_FACE_CAM_LIST=$FIXTURES/cam-list-rgb-and-ir.txt
export DELIGHT_FACE_GST=$STUB
export DELIGHT_FACE_GST_LOG=$SANDBOX/gst.log
export DELIGHT_FACE_GST_PIDS=$SANDBOX/gst.pids
export DELIGHT_FACE_MAX_SECONDS=5
export DELIGHT_FACE_STUB_SLEEP=30
: >"$DELIGHT_FACE_GST_LOG"
: >"$DELIGHT_FACE_GST_PIDS"

gst_stopped() {
  local pid state alive=0
  [[ -s $DELIGHT_FACE_GST_PIDS ]] || return 1
  while read -r pid || [[ -n $pid ]]; do
    [[ $pid =~ ^[0-9]+$ ]] || continue
    [[ -r /proc/$pid/stat ]] || continue
    state=$(sed -n 's/.*) //p' "/proc/$pid/stat" 2>/dev/null || true)
    state=${state%% *}
    if [[ -n $state && $state != Z ]]; then
      alive=1
    fi
  done <"$DELIGHT_FACE_GST_PIDS"
  [[ $alive -eq 0 ]]
}

ok "hold runs a command and stops the pipeline" timeout 10 "$BIN" hold -- true
ok "hold asked gstreamer for the HM1092 id" grep -F "camera-name=/base/soc/cci0/hm1092@24" "$DELIGHT_FACE_GST_LOG"
ok "hold asked for GRAY8" grep -F "format=GRAY8" "$DELIGHT_FACE_GST_LOG"
ok "hold inserted videoconvert" grep -F videoconvert "$DELIGHT_FACE_GST_LOG"
not_ok "hold did not pass camera-index" grep -F camera-index "$DELIGHT_FACE_GST_LOG"
not_ok "hold did not open the RGB sensor" grep -F ov02c10 "$DELIGHT_FACE_GST_LOG"
ok "hold stopped the gstreamer stand-in" gst_stopped

: >"$DELIGHT_FACE_GST_LOG"
: >"$DELIGHT_FACE_GST_PIDS"
export DELIGHT_FACE_CAM_LIST=$FIXTURES/cam-list-rgb-only.txt
rc=0
timeout 10 "$BIN" hold -- true >"$SANDBOX/hold.out" 2>"$SANDBOX/hold.err" || rc=$?
is "hold fails when no IR stream exists" "$rc" "1"
ok "hold failure is explicit" grep -F "no IR camera stream:" "$SANDBOX/hold.err"
ok "hold failure refuses an index" grep -F "Refusing to choose a camera by index" "$SANDBOX/hold.err"
not_ok "failed hold does not start gstreamer" test -s "$DELIGHT_FACE_GST_LOG"

export DELIGHT_FACE_CAM_LIST=$FIXTURES/cam-list-rgb-and-ir.txt
: >"$DELIGHT_FACE_GST_LOG"
: >"$DELIGHT_FACE_GST_PIDS"
armed=$("$BIN" arm 2>"$SANDBOX/arm.err")
is "arm returns the Howdy device path" "$armed" "/dev/v4l/by-id/delight-ir"
ok "arm started the grey pipeline" test -s "$DELIGHT_FACE_GST_LOG"
arm_pid=$(cat -- "$XDG_RUNTIME_DIR/omarchy-delight/face/arm.pid")
ok "arm recorded a pid" test -n "$arm_pid"

# kill -0 is true for a zombie. The capture has stopped once the process is
# gone or defunct (CI's PID 1 does not reap orphans).
capture_running() {
  local state
  [[ -r /proc/$arm_pid/stat ]] || return 1
  state=$(sed -n 's/.*) //p' "/proc/$arm_pid/stat" 2>/dev/null || true)
  state=${state%% *}
  [[ -n $state && $state != Z ]]
}

ok "arm is still streaming after it returns" capture_running
"$BIN" stop
stopped=1
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if ! capture_running; then
    stopped=0
    break
  fi
  sleep 0.1
done
if [[ $stopped != 0 ]]; then
  ps -p "$arm_pid" -o pid,ppid,stat,cmd >&2 || true
fi
is "stop ends the armed capture" "$stopped" "0"
ok "stop ended the gstreamer stand-in" gst_stopped
not_ok "stop clears the ready file" test -f "$XDG_RUNTIME_DIR/omarchy-delight/face/ready"

done_testing
