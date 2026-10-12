#!/bin/bash

# Backend selection matrix: role x portals x override.

source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"

sandbox
export PATH="$DELIGHT_TEST_REPO/modules/input/tests/stubs:$PATH"
export DELIGHT_ROOT="$DELIGHT_TEST_REPO"
# shellcheck source=../lib/backend.sh
source "$DELIGHT_TEST_REPO/lib/delight/delight.sh"
# shellcheck source=../lib/backend.sh
source "$DELIGHT_TEST_REPO/modules/input/lib/backend.sh"

select_with() {
  local portals="$1" role="$2" override="$3"
  INPUT_TEST_PORTALS="$portals" input_select_backend "$role" "$override"
}

field() {
  jq -r --arg k "$1" 'if .[$k] == null then "null" else .[$k] | tostring end'
}

check() {
  local desc="$1" portals="$2" role="$3" override="$4" want_backend="$5" want_override="$6" want_reason="$7"
  local out
  out=$(select_with "$portals" "$role" "$override")
  is "$desc: backend" "$(field backend <<<"$out")" "$want_backend"
  is "$desc: override" "$(field override <<<"$out")" "$want_override"
  if [[ $want_reason == "nonnull" ]]; then
    if jq -e '.reason != null' <<<"$out" >/dev/null; then
      TAP_COUNT=$((TAP_COUNT + 1))
      echo "ok $TAP_COUNT - $desc: reason non-null"
    else
      TAP_COUNT=$((TAP_COUNT + 1))
      echo "not ok $TAP_COUNT - $desc: reason non-null"
      TAP_FAILED=$((TAP_FAILED + 1))
    fi
  else
    is "$desc: reason" "$(field reason <<<"$out")" "null"
  fi
}

# share x auto
check "share auto no portals" "" share auto lan-mouse false nonnull
check "share auto InputCapture" "InputCapture" share auto deskflow false null
check "share auto RemoteDesktop" "RemoteDesktop" share auto lan-mouse false nonnull
check "share auto both" "InputCapture RemoteDesktop" share auto deskflow false null

# receive x auto
check "receive auto no portals" "" receive auto lan-mouse false nonnull
check "receive auto InputCapture" "InputCapture" receive auto lan-mouse false nonnull
check "receive auto RemoteDesktop" "RemoteDesktop" receive auto deskflow false null
check "receive auto both" "InputCapture RemoteDesktop" receive auto deskflow false null

# forced deskflow
check "share forced deskflow +IC" "InputCapture" share deskflow deskflow true null
check "share forced deskflow no IC" "" share deskflow deskflow true nonnull
check "receive forced deskflow +RD" "RemoteDesktop" receive deskflow deskflow true null
check "receive forced deskflow no RD" "" receive deskflow deskflow true nonnull

# forced lan-mouse
check "share forced lan-mouse" "InputCapture" share lan-mouse lan-mouse true null
check "receive forced lan-mouse" "" receive lan-mouse lan-mouse true null

# invalid inputs
not_ok "invalid role fails" input_select_backend sideways auto
not_ok "invalid backend fails" input_select_backend share synergy
not_ok "empty role fails" input_select_backend "" auto

done_testing
