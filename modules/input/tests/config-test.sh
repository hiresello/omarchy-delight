#!/bin/bash

# Golden fixtures for the pure config generators, plus set-peers validation.

source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"

sandbox
export PATH="$DELIGHT_TEST_REPO/modules/input/tests/stubs:$PATH"
export DELIGHT_ROOT="$DELIGHT_TEST_REPO"
# shellcheck source=../lib/config.sh
source "$DELIGHT_TEST_REPO/modules/input/lib/config.sh"

FIXTURES="$DELIGHT_TEST_REPO/modules/input/tests/fixtures"
BIN="$DELIGHT_TEST_REPO/modules/input/bin/delight-input"

SHARE_DESKFLOW='{"role":"share","backend":"deskflow","name":"omarchy","dir":"/cfg/input/deskflow","clipboard":true,"peers":[{"name":"mac","host":"mac.local","edge":"right","fingerprint":"AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"},{"name":"mini","host":"mini.local","edge":"left","fingerprint":""}]}'
RECV_DESKFLOW='{"role":"receive","backend":"deskflow","name":"omarchy","dir":"/cfg/input/deskflow","clipboard":true,"peers":[{"name":"mac","host":"mac.local","edge":"right","fingerprint":"aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"}]}'
SHARE_LANMOUSE='{"role":"share","backend":"lan-mouse","name":"omarchy","dir":"/cfg/input/lan-mouse","clipboard":true,"peers":[{"name":"mac","host":"mac.local","edge":"right","fingerprint":"AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"},{"name":"mini","host":"mini.local","edge":"left","fingerprint":""}]}'
RECV_LANMOUSE='{"role":"receive","backend":"lan-mouse","name":"omarchy","dir":"/cfg/input/lan-mouse","clipboard":true,"peers":[{"name":"mac","host":"mac.local","edge":"right","fingerprint":"AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"},{"name":"mini","host":"mini.local","edge":"left","fingerprint":""}]}'

is "share Deskflow.conf" "$(input_deskflow_ini "$SHARE_DESKFLOW")" "$(cat "$FIXTURES/share-Deskflow.conf")"
is "share deskflow-server.conf" "$(input_deskflow_server_conf "$SHARE_DESKFLOW")" "$(cat "$FIXTURES/share-deskflow-server.conf")"
is "share trusted-clients" "$(input_deskflow_trusted "$SHARE_DESKFLOW")" "$(cat "$FIXTURES/share-trusted-clients")"
is "receive Deskflow.conf" "$(input_deskflow_ini "$RECV_DESKFLOW")" "$(cat "$FIXTURES/receive-Deskflow.conf")"
is "receive trusted-servers" "$(input_deskflow_trusted "$RECV_DESKFLOW")" "$(cat "$FIXTURES/receive-trusted-servers")"
is "share lan-mouse config.toml" "$(input_lan_mouse_toml "$SHARE_LANMOUSE")" "$(cat "$FIXTURES/share-config.toml")"
is "receive lan-mouse config.toml" "$(input_lan_mouse_toml "$RECV_LANMOUSE")" "$(cat "$FIXTURES/receive-config.toml")"

# Fingerprint normalisation.
is "colon hex normalised" "$(input_fp_colons 'AA:BB:cc')" "aa:bb:cc"
is "plain hex gets colons" "$(input_fp_colons 'AABBcc')" "aa:bb:cc"
is "deskflow form" "$(input_fp_deskflow 'AA:BB:cc')" "v2:sha256:aabbcc"
not_ok "non-hex fingerprint rejected" input_fp_colons 'zz:11'

# set-peers validation (exit 64 on invalid input).
ok "set-peers accepts a valid array" "$BIN" set-peers '[{"name":"mac","host":"mac.local","edge":"right"}]'
"$BIN" set-peers '[{"name":"bad name!","host":"x","edge":"right"}]' >/dev/null 2>&1
is "bad name exits 64" "$?" "64"
"$BIN" set-peers '[{"name":"a","host":"x","edge":"diagonal"}]' >/dev/null 2>&1
is "bad edge exits 64" "$?" "64"
"$BIN" set-peers '[{"name":"a","host":"x","edge":"right"},{"name":"b","host":"y","edge":"right"}]' >/dev/null 2>&1
is "duplicate edge exits 64" "$?" "64"
"$BIN" set-peers '[{"name":"a","host":"","edge":"right"}]' >/dev/null 2>&1
is "empty host exits 64" "$?" "64"
"$BIN" set-peers 'not json' >/dev/null 2>&1
is "non-JSON exits 64" "$?" "64"

done_testing
