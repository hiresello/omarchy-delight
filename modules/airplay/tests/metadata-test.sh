#!/bin/bash

# shellcheck source=../../../tests/lib/tap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"

MODULE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BIN="$MODULE_DIR/bin/delight-airplay"
export DELIGHT_TEST_REPO

sandbox
export PATH="$MODULE_DIR/tests/stubs:$PATH"
printf '%s\n' "Desk" >"$DELIGHT_STUB_STATE/pretty-hostname"
touch "$DELIGHT_STUB_STATE/pkg-shairport-sync" "$DELIGHT_STUB_STATE/pkg-nqptp"

"$BIN" install
"$BIN" enable
touch "$DELIGHT_STUB_STATE/active-delight-airplay.service"
"$BIN" metadata-parse <"$MODULE_DIR/tests/fixtures/session.xml"

now_playing="$XDG_RUNTIME_DIR/omarchy-delight/airplay/now-playing.json"
is "sender metadata is decoded" "$(jq -r .sender "$now_playing")" "Juan's iPhone"
is "client IP is decoded" "$(jq -r .ip "$now_playing")" "192.168.1.42"
is "user agent is decoded" "$(jq -r .agent "$now_playing")" "AirPlay/2.0"
is "title is decoded from wrapped base64" "$(jq -r .title "$now_playing")" "Blue in Green"
is "artist is decoded from adjacent base64" "$(jq -r .artist "$now_playing")" "Miles Davis"
is "album is decoded from base64 without an internal newline" "$(jq -r .album "$now_playing")" "Kind of Blue"
is "playback state is true" "$(jq -r .playing "$now_playing")" "true"
is "notification is marked as sent" "$(jq -r .notified "$now_playing")" "true"

status=$("$BIN" status --json)
is "status subtitle shows title and artist" "$(jq -r .subtitle <<<"$status")" "Blue in Green · Miles Davis"
is "sender device kind is phone" "$(jq -r '.devices[0].kind' <<<"$status")" "phone"
ok "AirPlay status matches schema" schema_valid "$DELIGHT_TEST_REPO/schema/status.schema.json" <(printf '%s\n' "$status")
is "one start notification was sent" "$(grep -c 'AirPlay started from Juan' "$DELIGHT_STUB_LOG")" "1"

"$BIN" metadata-parse <"$MODULE_DIR/tests/fixtures/session.xml"
is "re-reading the same session does not notify again" "$(grep -c 'AirPlay started from Juan' "$DELIGHT_STUB_LOG")" "1"

"$BIN" metadata-parse <"$MODULE_DIR/tests/fixtures/end.xml"
status=$("$BIN" status --json)
is "end event returns subtitle to receiver name" "$(jq -r .subtitle <<<"$status")" "Receiving as Desk"
is "end event clears devices" "$(jq -c .devices <<<"$status")" "[]"

"$BIN" metadata-parse <"$MODULE_DIR/tests/fixtures/session.xml"
is "a new session re-arms the notification" "$(grep -c 'AirPlay started from Juan' "$DELIGHT_STUB_LOG")" "2"

ok "malformed and garbage lines do not crash parsing" bash -c 'printf "%s\n" garbage "<item>broken</item>" | "$1" metadata-parse' _ "$BIN"

done_testing
