#!/bin/bash

# Sensor selection is by libcamera id, never by camera index.

# shellcheck source=../../../tests/lib/tap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"

MODULE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BIN=$MODULE/bin/delight-face
FIXTURES=$MODULE/tests/fixtures

sandbox

select_rc() {
  local rc=0
  DELIGHT_FACE_CAM_LIST=$1 "$BIN" select >"$SANDBOX/select.out" 2>"$SANDBOX/select.err" || rc=$?
  printf '%s\n' "$rc"
}

is "hm1092 is chosen by id, not the first camera" \
  "$(DELIGHT_FACE_CAM_LIST=$FIXTURES/cam-list-rgb-and-ir.txt "$BIN" select)" \
  "/base/soc/cci0/hm1092@24"
not_ok "the RGB camera id is not selected" grep -F ov02c10 <<<"$(DELIGHT_FACE_CAM_LIST=$FIXTURES/cam-list-rgb-and-ir.txt "$BIN" select)"
not_ok "the selector output is not a camera index" grep -Ex '[0-9]+' <<<"$(DELIGHT_FACE_CAM_LIST=$FIXTURES/cam-list-rgb-and-ir.txt "$BIN" select)"

is "sensor match is case-insensitive and still returns the id path" \
  "$(DELIGHT_FACE_CAM_LIST=$FIXTURES/cam-list-case.txt "$BIN" select)" \
  "/base/soc/cci0/HM1092@24"

is "rgb-only list fails" "$(select_rc "$FIXTURES/cam-list-rgb-only.txt")" "1"
ok "rgb-only failure names the missing stream" grep -F "no IR camera stream:" "$SANDBOX/select.err"
ok "rgb-only failure names hm1092" grep -F "hm1092" "$SANDBOX/select.err"
ok "rgb-only failure refuses an index" grep -F "Refusing to choose a camera by index" "$SANDBOX/select.err"
ok "rgb-only failure says the A16 result is unverified" grep -F "unverified" "$SANDBOX/select.err"
not_ok "rgb-only failure does not print an id" test -s "$SANDBOX/select.out"

is "empty camera list fails" "$(select_rc "$FIXTURES/cam-list-empty.txt")" "1"
ok "empty list reports no IR stream" grep -F "no IR camera stream:" "$SANDBOX/select.err"

is "two HM1092 cameras fail closed" "$(select_rc "$FIXTURES/cam-list-two-ir.txt")" "1"
ok "two matches refuse an index" grep -F "more than one libcamera camera matches sensor 'hm1092'" "$SANDBOX/select.err"
not_ok "two matches do not pick the first id" grep -F "/base/soc/cci0/hm1092@24" "$SANDBOX/select.out"

is "a name without an id fails closed" "$(select_rc "$FIXTURES/cam-list-no-id.txt")" "1"
ok "missing id is explained" grep -F "no camera id" "$SANDBOX/select.err"
not_ok "missing id does not fall back to 1" grep -Ex '1' "$SANDBOX/select.out"

pipeline=$(DELIGHT_FACE_SOURCE=libcamera DELIGHT_FACE_SINK=v4l2 DELIGHT_FACE_CAM_LIST=$FIXTURES/cam-list-rgb-and-ir.txt "$BIN" pipeline)
ok "pipeline uses libcamerasrc camera-name" grep -F "camera-name=/base/soc/cci0/hm1092@24" <<<"$pipeline"
ok "pipeline converts to GRAY8" grep -F "format=GRAY8" <<<"$pipeline"
ok "pipeline writes the stable loopback path" grep -F "device=/dev/v4l/by-id/delight-ir" <<<"$pipeline"
ok "pipeline uses v4l2sink" grep -F v4l2sink <<<"$pipeline"
not_ok "pipeline does not set camera-index" grep -F camera-index <<<"$pipeline"
not_ok "pipeline does not open the RGB sensor" grep -F ov02c10 <<<"$pipeline"

standin=$(DELIGHT_FACE_SOURCE=videotestsrc DELIGHT_FACE_SINK=fakesink "$BIN" pipeline)
ok "videotestsrc stand-in is explicit" grep -F videotestsrc <<<"$standin"
ok "stand-in is grey" grep -F "format=GRAY8" <<<"$standin"
not_ok "stand-in does not pretend to be libcamerasrc" grep -F libcamerasrc <<<"$standin"

rc=0
DELIGHT_FACE_SOURCE=libcamera DELIGHT_FACE_CAM_LIST=$FIXTURES/cam-list-rgb-only.txt "$BIN" pipeline >/dev/null 2>"$SANDBOX/pipeline.err" || rc=$?
is "pipeline refuses to build without an IR stream" "$rc" "1"
ok "pipeline refusal is the no-stream error" grep -F "no IR camera stream:" "$SANDBOX/pipeline.err"

done_testing
