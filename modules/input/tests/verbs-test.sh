#!/bin/bash

# End-to-end verbs in the sandbox with the module's own stubs on PATH.

source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"

sandbox
export PATH="$DELIGHT_TEST_REPO/modules/input/tests/stubs:$PATH"

BIN="$DELIGHT_TEST_REPO/modules/input/bin/delight-input"
INPUT_DIR="$HOME/.config/omarchy-delight/input"
SCHEMA="$DELIGHT_TEST_REPO/schema"

export INPUT_TEST_PORTALS="InputCapture"
export INPUT_TEST_HOSTNAME="omarchy"

ok "install" "$BIN" install

ok "enable --role share" "$BIN" enable --role share
is "backend file is deskflow" "$(cat "$INPUT_DIR/backend")" "deskflow"
ok "unit enabled via systemctl" grep -q 'systemctl --user enable --now delight-input.service' "$DELIGHT_STUB_LOG"
not_ok "no open firewall rule (from any)" grep -Eq 'from (any|0\.0\.0\.0)' "$DELIGHT_STUB_LOG"
for cidr in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
  ok "ufw rule for $cidr" grep -q "ufw allow in proto tcp from $cidr to any port 24800" "$DELIGHT_STUB_LOG"
done

# Re-enabling an already-enabled module restarts the unit.
ok "re-enable" "$BIN" enable --role share
ok "re-enable restarts unit" grep -q 'systemctl --user restart delight-input.service' "$DELIGHT_STUB_LOG"

doctor_out=$("$BIN" doctor || true)
ok "doctor sees InputCapture" grep -q 'InputCapture portal: present' <<<"$doctor_out"
ok "doctor names backend" grep -q 'backend: deskflow' <<<"$doctor_out"

# Receiving without a RemoteDesktop portal falls back to Lan Mouse.
ok "enable --role receive" "$BIN" enable --role receive
is "backend file is lan-mouse" "$(cat "$INPUT_DIR/backend")" "lan-mouse"
status=$("$BIN" status --json)
is "status on" "$(jq -r .state <<<"$status")" "on"
ok "status explains fallback" jq -e '.reason != null' <<<"$status"
is "status mentions Lan Mouse" "$(jq -r .subtitle <<<"$status" | grep -c 'Lan Mouse')" "1"

# devices --json is schema-valid even without peers.
ok "devices --json matches schema" schema_valid "$SCHEMA/device.schema.json" <("$BIN" devices --json)

# With a peer and a stubbed lan-mouse cli list.
"$BIN" set-peers '[{"name":"mac","host":"mac.local","edge":"right"}]'
INPUT_TEST_LANMOUSE="$SANDBOX/lan-mouse-list"
printf 'id 0: mac.local:4242 (right) active: true, ips: {10.0.0.5}\n' >"$INPUT_TEST_LANMOUSE"
export INPUT_TEST_LANMOUSE
devices=$("$BIN" devices --json)
is "peer connected via lan-mouse list" "$(jq -r '.[0].connected' <<<"$devices")" "true"
is "peer kind" "$(jq -r '.[0].kind' <<<"$devices")" "computer"
is "peer transport" "$(jq -r '.[0].transport' <<<"$devices")" "lan-mouse"
printf 'id 0: mac.local:4242 (right) active: false, ips: {}\n' >"$INPUT_TEST_LANMOUSE"
is "peer disconnected" "$(jq -r '.[0].connected' <<<"$("$BIN" devices --json)")" "false"

# fingerprint --json always exits 0.
ok "fingerprint --json" "$BIN" fingerprint --json
is "fingerprint backend" "$("$BIN" fingerprint --json | jq -r .backend)" "lan-mouse"

ok "uninstall" "$BIN" uninstall
not_ok "generated dir removed" test -e "$INPUT_DIR"
not_ok "state removed" test -e "$HOME/.local/state/omarchy-delight/input"
not_ok "status file removed" test -e "$XDG_RUNTIME_DIR/omarchy-delight/status/input.json"
ok "ufw rules deleted" grep -q 'ufw delete allow in proto tcp from 10.0.0.0/8' "$DELIGHT_STUB_LOG"

done_testing
