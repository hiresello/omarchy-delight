#!/bin/bash

# shellcheck source=../../../tests/lib/tap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"

MODULE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BIN="$MODULE_DIR/bin/delight-airplay"
export DELIGHT_TEST_REPO

sandbox
export PATH="$MODULE_DIR/tests/stubs:$PATH"

ok "default configuration is byte-exact" cmp "$MODULE_DIR/tests/golden/shairport-sync.conf" <("$BIN" render-conf Desk /run/user/1000/omarchy-delight/airplay/metadata)
ok "libconfig name escaping handles quotes and backslashes" "$BIN" render-conf 'Juan "Desk" \ Mac' /run/user/1000/metadata

escape_conf=$("$BIN" render-conf 'Juan "Desk" \ Mac' /run/user/1000/metadata)
is "escaped name is valid libconfig string text" "$(sed -n 's/^  name = "\(.*\)";$/\1/p' <<<"$escape_conf")" 'Juan \"Desk\" \\ Mac'

source "$DELIGHT_TEST_REPO/lib/delight/delight.sh"
# shellcheck source=../lib/airplay.sh
source "$MODULE_DIR/lib/airplay.sh"

mkdir -p "$DELIGHT_CONFIG_DIR"
printf '%s\n' '{"schema":1,"modules":{"airplay":{"name":"Configured"}}}' >"$DELIGHT_CONFIG_FILE"
printf '%s\n' "Pretty Host" >"$DELIGHT_STUB_STATE/pretty-hostname"
is "configured name takes precedence" "$(airplay_name)" "Configured"

printf '%s\n' '{"schema":1,"modules":{"airplay":{"name":null}}}' >"$DELIGHT_CONFIG_FILE"
is "pretty hostname is used when the configured name is null" "$(airplay_name)" "Pretty Host"

: >"$DELIGHT_STUB_STATE/pretty-hostname"
expected_name=$(uname -n)
if [[ -r /etc/machine-info ]]; then
  machine_pretty=$(sed -n 's/^PRETTY_HOSTNAME=//p' /etc/machine-info | head -n 1)
  machine_pretty=${machine_pretty#\"}
  machine_pretty=${machine_pretty%\"}
  machine_pretty=${machine_pretty#\'}
  machine_pretty=${machine_pretty%\'}
  if [[ -n $machine_pretty ]]; then
    expected_name=$machine_pretty
  fi
fi
is "empty pretty hostname falls back through machine-info to uname" "$(airplay_name)" "${expected_name:0:50}"

delight_config_set airplay name "$(jq -cn --arg v "$(printf 'x%.0s' {1..60})" '$v')"
name=$(airplay_name)
is "resolved names are truncated to 50 characters" "${#name}" "50"

done_testing
