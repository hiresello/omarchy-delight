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

# --- sheet ------------------------------------------------------------------

: >"$DELIGHT_STUB_LOG"
ok "sheet with paths summons the panel" "$BIN" sheet "$testfile"
ok "sheet ran omarchy-shell summon delight.share" grep -q "omarchy-shell shell summon delight.share" "$DELIGHT_STUB_LOG"
ok "sheet payload carries the file path" grep -q "$testfile" "$DELIGHT_STUB_LOG"

echo clip-bytes >"$DELIGHT_STUB_STATE/clipboard"
: >"$DELIGHT_STUB_LOG"
ok "sheet --clipboard summons the panel" "$BIN" sheet --clipboard
ok "clipboard summon happened" grep -q "omarchy-shell shell summon delight.share" "$DELIGHT_STUB_LOG"

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

: >"$DELIGHT_STUB_LOG"
ok "watch-receive --once exits 0" "$BIN" watch-receive --once --prefs "$prefs"
ok "notify for received file" grep -q "omarchy-notification-send.*Received note.txt" "$DELIGHT_STUB_LOG"
ok "file notify offers reveal exec" grep -q "exec nautilus --select" "$DELIGHT_STUB_LOG"
ok "message notify" grep -q "Message from Desk" "$DELIGHT_STUB_LOG"

: >"$DELIGHT_STUB_LOG"
"$BIN" watch-receive --once --prefs "$prefs" >/dev/null 2>&1
not_ok "second --once notifies nothing new" grep -q "omarchy-notification-send" "$DELIGHT_STUB_LOG"

done_testing
