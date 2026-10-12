#!/bin/bash

source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/test-lib"

hotspot_test_init
hotspot_nm_fixture
hotspot_bt_fixture
bin="$DELIGHT_TEST_REPO/modules/hotspot/bin/delight-hotspot"
hotspot_install

desk=$("$bin" trace replay "$DELIGHT_TEST_REPO/modules/hotspot/tests/traces/desk-1h.tsv")
is "desk trace has exactly one initial transition" "$(wc -l <<<"$desk")" "1"
ok "desk trace transitions to near" grep -q $'\tnear\t' <<<"$desk"
not_ok "desk trace has no false away transition" grep -q $'\taway\t' <<<"$desk"

walk=$("$bin" trace replay "$DELIGHT_TEST_REPO/modules/hotspot/tests/traces/walk-away.tsv")
away_at=$(awk -F '\t' '$3 == "away" { print $1; exit }' <<<"$walk")
ok "walk-away crosses away dwell no earlier than 80+120s" test "$away_at" -ge 200
ok "walk-away changes before one 20s interval after dwell" test "$away_at" -lt 221

edge=$("$bin" trace replay "$DELIGHT_TEST_REPO/modules/hotspot/tests/traces/edge-flap.tsv")
ok "edge flap causes at most one transition" test "$(wc -l <<<"$edge")" -le 1

return_trace=$("$bin" trace replay "$DELIGHT_TEST_REPO/modules/hotspot/tests/traces/return.tsv")
is "return trace transitions back to near after dwell" "$(awk -F '\t' '$3 == "near" { print $3 }' <<<"$return_trace" | tail -n1)" "near"

suspend=$("$bin" trace replay "$DELIGHT_TEST_REPO/modules/hotspot/tests/traces/suspend-gap.tsv")
resume_away=$(awk -F '\t' '$3 == "away" { print $1; exit }' <<<"$suspend")
ok "suspend gap restarts away dwell" test "$resume_away" -ge 3720

connected=$("$bin" trace replay "$DELIGHT_TEST_REPO/modules/hotspot/tests/traces/connected-no-rssi.tsv")
is "connected phone without RSSI reaches near" "$(awk -F '\t' '$3 == "near" { print $3 }' <<<"$connected" | tail -n1)" "near"
not_ok "connected phone without RSSI never becomes away" grep -q $'\taway\t' <<<"$connected"

done_testing
