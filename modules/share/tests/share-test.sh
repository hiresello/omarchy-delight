#!/bin/bash

# TAP tests for the share module. Stubs in ./stubs shadow system commands.

set -uo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"

sandbox

SHARE_STUBS="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/stubs" && pwd)"
export PATH="$SHARE_STUBS:$PATH"

BIN="$DELIGHT_TEST_REPO/modules/share/bin/delight-share"
SCHEMA="$DELIGHT_TEST_REPO/schema"

# --- share-targets ----------------------------------------------------------

DELIGHT_SHARE_PEERS_FIXTURE="$SANDBOX/peers.json"
export DELIGHT_SHARE_PEERS_FIXTURE
cat >"$DELIGHT_SHARE_PEERS_FIXTURE" <<'EOF'
[
  {"alias":"Pixel 8","version":"2.2","deviceType":"mobile","fingerprint":"abc123","ip":"192.168.1.20","protocol":"https"},
  {"alias":"Desk","version":"2.2","deviceType":"desktop","fingerprint":"def456","ip":"192.168.1.10","protocol":"https"}
]
EOF

out=$("$BIN" share-targets --json)
ok "share-targets fixture validates against schema" schema_valid "$SCHEMA/share-target.schema.json" <(printf '%s' "$out")
is "share-targets fixture count" "$(jq length <<<"$out")" "2"
is "share-targets maps mobile to phone" "$(jq -r '.[0].kind' <<<"$out")" "phone"
is "share-targets id has localsend prefix" "$(jq -r '.[0].id | startswith("localsend:")' <<<"$out")" "true"
is "share-targets label from alias" "$(jq -r '.[0].label' <<<"$out")" "Pixel 8"

echo '[]' >"$DELIGHT_SHARE_PEERS_FIXTURE"
out=$("$BIN" share-targets --json)
is "share-targets empty peers gives []" "$out" "[]"
ok "share-targets [] validates" schema_valid "$SCHEMA/share-target.schema.json" <(printf '%s' "$out")

unset DELIGHT_SHARE_PEERS_FIXTURE
out=$("$BIN" share-targets --json) # stubbed ip reports no interfaces
is "share-targets with no network gives []" "$out" "[]"
ok "share-targets never exits non-zero" "$BIN" share-targets --json

# Live discovery: one RFC1918 iface, curl answers /register only for .20.
echo "192.168.50.10" >"$DELIGHT_STUB_STATE/ips"
echo '192.168.50.20 {"alias":"Pixel 8","version":"2.2","deviceType":"mobile","fingerprint":"fp1"}' \
  >"$DELIGHT_STUB_STATE/net-peers"
"$DELIGHT_TEST_REPO/bin/delight" config set share.discoveryTimeout 1 >/dev/null
rm -f "$XDG_RUNTIME_DIR/omarchy-delight/share/peers.json"
out=$("$BIN" share-targets --json)
is "discovery finds the one peer" "$(jq length <<<"$out")" "1"
is "peer cached with ip+protocol" \
  "$(jq -r '.[0] | "\(.ip) \(.protocol)"' "$XDG_RUNTIME_DIR/omarchy-delight/share/peers.json")" "192.168.50.20 https"
is "discovered target id uses fingerprint" "$(jq -r '.[0].id' <<<"$out")" "localsend:fp1"
is "discovered target kind is phone" "$(jq -r '.[0].kind' <<<"$out")" "phone"
rm -f "$DELIGHT_STUB_STATE/ips" "$DELIGHT_STUB_STATE/net-peers"

# --- doctor / enable --airdrop ----------------------------------------------

rc=0
doctor_out=$("$BIN" doctor --airdrop 2>&1) || rc=$?
is "doctor --airdrop without monitor exits 2" "$rc" "2"
ok "doctor --airdrop prints a reason" grep -qi "monitor" <<<"$doctor_out"

rc=0
"$BIN" enable --airdrop >/dev/null 2>&1 || rc=$?
is "enable --airdrop without monitor exits 2" "$rc" "2"
is "airdrop stays false after refused enable" "$("$BIN" status --json | jq -r '.state')" "needs-setup"

touch "$DELIGHT_STUB_STATE/iw-monitor"
dry=$(DELIGHT_DRY_RUN=1 "$BIN" enable --airdrop 2>&1)
ok "enable --airdrop dry-run succeeds with monitor" test $? -eq 0
ok "dry-run adds AUR opendrop" grep -q "aur-add opendrop\|opendrop" <<<"$dry"
ok "dry-run adds AUR owlink-git" grep -q "owlink-git" <<<"$dry"

rm -f "$DELIGHT_STUB_STATE/iw-monitor"

# --- send -------------------------------------------------------------------

testfile="$SANDBOX/photo.jpg"
echo fake-jpeg >"$testfile"
: >"$DELIGHT_STUB_LOG"

touch "$DELIGHT_STUB_STATE/localsend-to"
ok "send via localsend --to exits 0" "$BIN" send localsend:192.168.1.20 "$testfile"
ok "send called localsend with --to and the path" \
  grep -q "localsend --headless send --to 192.168.1.20 .*$testfile\|localsend.*send --to 192.168.1.20 .*$testfile" "$DELIGHT_STUB_LOG"

rc=0
"$BIN" send banana:xyz "$testfile" >/dev/null 2>&1 || rc=$?
ok "send unknown target prefix exits non-zero" test "$rc" -ne 0

# Protocol fallback: localsend help lacks --to, so send speaks HTTP via curl.
rm -f "$DELIGHT_STUB_STATE/localsend-to"
: >"$DELIGHT_STUB_LOG"
ok "protocol fallback send exits 0" "$BIN" send localsend:192.168.1.20 "$testfile"
ok "prepare-upload sent info and file metadata" \
  grep -q "prepare-upload" "$DELIGHT_STUB_LOG" -a \
  && grep -Eq 'curl .*-d .*"info".*"files".*"f0".*photo\.jpg' "$DELIGHT_STUB_LOG"
ok "upload used sessionId/fileId/token" \
  grep -q "upload?sessionId=s1&fileId=f0&token=tok" "$DELIGHT_STUB_LOG"

echo 403 >"$DELIGHT_STUB_STATE/curl-code"
: >"$DELIGHT_STUB_LOG"
rc=0
"$BIN" send localsend:192.168.1.20 "$testfile" >/dev/null 2>&1 || rc=$?
is "403 from prepare-upload exits 1" "$rc" "1"
ok "403 sends Send failed notification" grep -q "Send failed" "$DELIGHT_STUB_LOG"
rm -f "$DELIGHT_STUB_STATE/curl-code"

# --- AirDrop targets --------------------------------------------------------

touch "$DELIGHT_STUB_STATE/iw-monitor"
"$DELIGHT_TEST_REPO/bin/delight" config set share.airdrop true >/dev/null
cat >"$DELIGHT_STUB_STATE/opendrop-peers" <<'EOF'
Looking for receivers. Press Ctrl+C to stop ...
Found  index 0  ID a1b2c3d4e5f6  name Apple iPhone
Found  index 1  ID 001122334455  name Tim's MacBook
EOF
rm -f "$XDG_RUNTIME_DIR/omarchy-delight/share/peers.json" # drop cached []
out=$("$BIN" share-targets --json)
ok "airdrop targets validate against schema" schema_valid "$SCHEMA/share-target.schema.json" <(printf '%s' "$out")
is "two airdrop targets" "$(jq 'map(select(.id | startswith("airdrop:"))) | length' <<<"$out")" "2"
is "airdrop id uses opendrop ID" "$(jq -r 'map(.id) | index("airdrop:a1b2c3d4e5f6") != null' <<<"$out")" "true"
is "airdrop label uses name" "$(jq -r '.[] | select(.id == "airdrop:a1b2c3d4e5f6") | .label' <<<"$out")" "Apple iPhone"
"$DELIGHT_TEST_REPO/bin/delight" config set share.airdrop false >/dev/null
rm -f "$DELIGHT_STUB_STATE/iw-monitor" "$DELIGHT_STUB_STATE/opendrop-peers"

# --- sheet ------------------------------------------------------------------

: >"$DELIGHT_STUB_LOG"
ok "sheet with paths summons the panel" "$BIN" sheet "$testfile"
ok "sheet ran omarchy-shell summon delight.share" grep -q "omarchy-shell shell summon delight.share" "$DELIGHT_STUB_LOG"
ok "sheet payload carries the file path" grep -q "$testfile" "$DELIGHT_STUB_LOG"

echo clip-bytes >"$DELIGHT_STUB_STATE/clipboard"
echo "image/png" >"$DELIGHT_STUB_STATE/clipboard-type"
: >"$DELIGHT_STUB_LOG"
ok "sheet --clipboard summons the panel" "$BIN" sheet --clipboard
ok "clipboard summon happened" grep -q "omarchy-shell shell summon delight.share" "$DELIGHT_STUB_LOG"
ok "clipboard file gets .png extension" grep -q 'clipboard-[0-9]*\.png' "$DELIGHT_STUB_LOG"
rm -f "$DELIGHT_STUB_STATE/clipboard-type"

rc=0
"$BIN" sheet "$SANDBOX/does-not-exist.jpg" >/dev/null 2>&1 || rc=$?
is "sheet rejects a nonexistent path" "$rc" "64"

# --- install / nautilus extension -------------------------------------------

mkdir -p "$HOME/.local/share/nautilus-python/extensions"
echo ORIGINAL >"$HOME/.local/share/nautilus-python/extensions/localsend.py"
before=$(sha256sum <"$HOME/.local/share/nautilus-python/extensions/localsend.py")

ok "install" "$BIN" install
ok "nautilus extension installed" test -f "$HOME/.local/share/nautilus-python/extensions/delight-share.py"
is "localsend.py untouched" "$(sha256sum <"$HOME/.local/share/nautilus-python/extensions/localsend.py")" "$before"

ok "uninstall" "$BIN" uninstall
not_ok "our nautilus extension removed" test -e "$HOME/.local/share/nautilus-python/extensions/delight-share.py"
is "localsend.py still untouched" "$(sha256sum <"$HOME/.local/share/nautilus-python/extensions/localsend.py")" "$before"

# --- watch-receive ----------------------------------------------------------

prefs="$SANDBOX/shared_preferences.json"
cat >"$prefs" <<'EOF'
{"flutter.ls_receive_history":[
  "{\"id\":\"r1\",\"fileName\":\"note.txt\",\"fileType\":\"text/plain\",\"path\":\"/home/u/Downloads/note.txt\",\"isMessage\":false,\"fileSize\":10,\"senderAlias\":\"Pixel 8\",\"timestamp\":\"2026-10-12T00:00:00Z\"}",
  "{\"id\":\"r2\",\"fileName\":\"hi there\",\"isMessage\":true,\"senderAlias\":\"Desk\",\"timestamp\":\"2026-10-12T00:00:01Z\"}"
]}
EOF

# First pass seeds the seen file: no notifications for historic entries.
: >"$DELIGHT_STUB_LOG"
ok "watch-receive --once exits 0" "$BIN" watch-receive --once --prefs "$prefs"
not_ok "first --once seeds without notifying" grep -q "omarchy-notification-send" "$DELIGHT_STUB_LOG"

# A genuinely new entry notifies once, with a reveal action.
jq '.["flutter.ls_receive_history"] += ["{\"id\":\"r3\",\"fileName\":\"pic.png\",\"fileType\":\"image/png\",\"path\":\"/home/u/Pictures/pic.png\",\"isMessage\":false,\"fileSize\":99,\"senderAlias\":\"Pixel 8\",\"timestamp\":\"2026-10-12T00:00:02Z\"}"]' \
  "$prefs" >"$prefs.new" && mv "$prefs.new" "$prefs"
: >"$DELIGHT_STUB_LOG"
ok "watch-receive --once again exits 0" "$BIN" watch-receive --once --prefs "$prefs"
is "exactly one new notification" "$(grep -c omarchy-notification-send "$DELIGHT_STUB_LOG")" "1"
ok "file notify offers reveal exec" grep -q "exec nautilus --select /home/u/Pictures/pic.png" "$DELIGHT_STUB_LOG"
ok "new-entry notify names the file" grep -q "Received pic.png" "$DELIGHT_STUB_LOG"

: >"$DELIGHT_STUB_LOG"
"$BIN" watch-receive --once --prefs "$prefs" >/dev/null 2>&1
not_ok "third --once notifies nothing" grep -q "omarchy-notification-send" "$DELIGHT_STUB_LOG"

done_testing
