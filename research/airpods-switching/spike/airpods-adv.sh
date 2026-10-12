#!/bin/bash
# Research spike: decode one AirPods "Proximity Pairing" BLE advertisement
# (Apple company id 0x004C manufacturer data) into JSON.
# Standalone spike only; not wired into install; does not source lib/ or
# reference modules/.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: airpods-adv.sh [--help | --self-test] [HEX]

Decode one AirPods "Proximity Pairing" manufacturer-data payload into JSON.
HEX is the payload AFTER the Apple company id, starting "07 19 01 ...".
Spaces/colons are ignored, case is ignored, and a leading "4c00" (the
company id itself) is stripped if present. Reads stdin when HEX is omitted.

Getting the bytes:
  bluetoothctl   run `scan on`, then `info <addr>` shows a
                 "ManufacturerData Key: 0x004C" entry whose value bytes
                 are this payload.
  btmon          run `sudo btmon` while the AirPods advertise; look for
                 "Company: Apple Inc. (76)" manufacturer data.

Layout per https://github.com/furiousMAC/continuity/blob/master/messages/proximity_pairing.md
EOF
}

die() {
  echo "airpods-adv: $*" >&2
  exit 2
}

# Decode one battery nibble to a percent, or "null" for 0xF (unknown).
nib_pct() {
  local n=$((16#$1))
  if ((n == 15)); then
    printf 'null'
  else
    printf '%d' $((n * 10))
  fi
}

# Model-name table from public reverse engineering (furiousMAC/continuity,
# community reports); unverified, best-effort. Unknown model -> null.
model_name() {
  case $1 in
    0220) printf '"AirPods"' ;;
    0f20) printf '"AirPods (2nd gen)"' ;;
    1320) printf '"AirPods (3rd gen)"' ;;
    0e20) printf '"AirPods Pro"' ;;
    1420) printf '"AirPods Pro (2nd gen)"' ;;
    0a20) printf '"AirPods Max"' ;;
    *) printf 'null' ;;
  esac
}

decode() {
  local raw=$1 hex
  hex=$(printf '%s' "$raw" | tr -d '[:space:]:' | tr 'A-F' 'a-f')
  [[ -n $hex ]] || die "empty input"
  [[ $hex =~ ^[0-9a-f]+$ ]] || die "non-hex characters in input"
  ((${#hex} % 2 == 0)) || die "odd number of hex digits"
  if [[ $hex == 4c00* ]]; then
    hex=${hex:4}
  fi

  local total=$((${#hex} / 2))
  ((total >= 1)) || die "no payload after company id"
  [[ ${hex:0:2} == "07" ]] || die "not a proximity-pairing message (type 0x${hex:0:2})"
  ((total >= 11)) || die "truncated input: need >= 11 bytes, got $total"

  local model="${hex:6:2}${hex:8:2}"
  local status="0x${hex:10:2}"
  local bat="${hex:12:2}" flags="${hex:14:2}"
  local right left kase
  right=$(nib_pct "${bat:0:1}")
  left=$(nib_pct "${bat:1:1}")
  kase=$(nib_pct "${flags:1:1}")
  local charging="0x${flags:0:1}"
  local lid=$((16#${hex:16:2})) color=$((16#${hex:18:2}))
  local encrypted=null name_json
  name_json=$(model_name "$model")
  if ((total >= 27)); then
    encrypted="\"${hex:22:32}\""
  fi

  # status and chargingFlags are emitted raw: their bit meanings
  # (in-ear, which bud is charging) are not verified.
  jq -n \
    --arg model "$model" \
    --argjson modelName "$name_json" \
    --arg status "$status" \
    --argjson left "$left" \
    --argjson right "$right" \
    --argjson case "$kase" \
    --arg charging "$charging" \
    --argjson lid "$lid" \
    --argjson color "$color" \
    --argjson encrypted "$encrypted" \
    '{
      type: "proximity-pairing",
      model: $model,
      modelName: $modelName,
      status: $status,
      battery: {left: $left, right: $right, case: $case},
      chargingFlags: $charging,
      lidOpenCount: $lid,
      color: $color,
      encrypted: $encrypted
    }'
}

self_test() {
  local good='4c00 07 19 01 0e 20 55 6f 1a 02 01 00 00112233445566778899aabbccddeeff'
  local badtype='08 19 01 0e 20 55 6f 1a 02 01 00'
  local truncated='07 19 01'
  local rc=0 fails=0

  echo '1..3'
  if decode "$good" | jq -e '
      .type == "proximity-pairing" and
      .model == "0e20" and
      .modelName == "AirPods Pro" and
      .status == "0x55" and
      .battery.left == null and
      .battery.right == 60 and
      .battery.case == 100 and
      .chargingFlags == "0x1" and
      .lidOpenCount == 2 and
      .color == 1 and
      .encrypted == "00112233445566778899aabbccddeeff"' >/dev/null; then
    echo 'ok 1 - well-formed fixture decodes to expected JSON'
  else
    echo 'not ok 1 - well-formed fixture decodes to expected JSON'
    fails=1
  fi

  (decode "$badtype" >/dev/null 2>&1) || rc=$?
  if ((rc == 2)); then
    echo 'ok 2 - wrong type byte rejected with exit 2'
  else
    echo "not ok 2 - wrong type byte rejected with exit 2 (rc=$rc)"
    fails=1
  fi

  rc=0
  (decode "$truncated" >/dev/null 2>&1) || rc=$?
  if ((rc == 2)); then
    echo 'ok 3 - truncated input rejected with exit 2'
  else
    echo "not ok 3 - truncated input rejected with exit 2 (rc=$rc)"
    fails=1
  fi

  exit "$fails"
}

case ${1:-} in
  --help)
    usage
    exit 0
    ;;
  --self-test)
    self_test
    ;;
esac

if (($#)); then
  decode "$1"
else
  decode "$(cat)"
fi
