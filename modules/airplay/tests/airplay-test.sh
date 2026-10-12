#!/bin/bash

# shellcheck source=../../../tests/lib/tap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"

MODULE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BIN="$MODULE_DIR/bin/delight-airplay"
export DELIGHT_TEST_REPO

sandbox
export PATH="$MODULE_DIR/tests/stubs:$PATH"
printf '%s\n' "Install Host" >"$DELIGHT_STUB_STATE/pretty-hostname"

"$BIN" install
touch "$DELIGHT_STUB_STATE/pkg-shairport-sync" "$DELIGHT_STUB_STATE/pkg-nqptp"

is "install records that Delight enabled nqptp" "$(jq -r '.flags.nqptpEnabled' "$HOME/.local/state/omarchy-delight/airplay/installed.json")" "true"
ok "installation writes the receiver configuration" test -f "$HOME/.config/omarchy-delight/airplay/shairport-sync.conf"
ok "installed configuration matches the resolved name and FIFO path" cmp "$HOME/.config/omarchy-delight/airplay/shairport-sync.conf" <("$BIN" render-conf "Install Host" "$XDG_RUNTIME_DIR/omarchy-delight/airplay/metadata")

while IFS=$'\t' read -r proto ports; do
  [[ -n $proto ]] || continue
  for cidr in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
    ok "install opens $proto $ports only to $cidr" grep -F "ufw allow in proto $proto from $cidr to any port $ports comment omarchy-delight:airplay" "$DELIGHT_STUB_LOG"
  done
done < <(jq -r '.firewall[] | [.proto, .ports] | @tsv' "$MODULE_DIR/module.json")
ok "no install firewall rule is public" awk '/ufw allow/ && $0 !~ / from / && $0 !~ / on tailscale0 / { bad = 1 } END { exit bad }' "$DELIGHT_STUB_LOG"

"$BIN" rename Desk
is "rename stores a JSON string" "$(jq -r '.modules.airplay.name | type' "$HOME/.config/omarchy-delight/config.json")" "string"
is "rename updates the generated name" "$(sed -n 's/^  name = "\(.*\)";$/\1/p' "$HOME/.config/omarchy-delight/airplay/shairport-sync.conf")" "Desk"
not_ok "rename does not restart the receiver while disabled" grep -F 'try-restart delight-airplay.service' "$DELIGHT_STUB_LOG"

"$BIN" enable
"$BIN" rename 123
is "numeric-looking rename stays a string" "$(jq -r '.modules.airplay.name | type' "$HOME/.config/omarchy-delight/config.json")" "string"
ok "rename restarts the enabled receiver" grep -F 'try-restart delight-airplay.service' "$DELIGHT_STUB_LOG"

invalid_name() {
  local expected_rc=64 rc=0
  "$BIN" rename "$@" >/dev/null 2>&1 || rc=$?
  is "invalid rename is rejected with exit 64" "$rc" "$expected_rc"
}
invalid_name '%h'
invalid_name ""
invalid_name "$(printf 'x%.0s' {1..51})"

rm -f "$DELIGHT_STUB_STATE/active-delight-airplay.service"
printf '%s\n' activating >"$DELIGHT_STUB_STATE/state-delight-airplay.service"
is "activating status maps to busy" "$("$BIN" status --json | jq -r .state)" "busy"
rm -f "$DELIGHT_STUB_STATE/state-delight-airplay.service"
is "enabled inactive status maps to error" "$("$BIN" status --json | jq -r .state)" "error"
ok "inactive status explains how to diagnose" "$BIN" status --json
reason=$("$BIN" status --json | jq -r .reason)
ok "inactive status reason recommends doctor" grep -F 'run: delight airplay doctor' <<<"$reason"

touch "$DELIGHT_STUB_STATE/active-avahi-daemon.service" \
  "$DELIGHT_STUB_STATE/active-nqptp.service" \
  "$DELIGHT_STUB_STATE/active-pipewire.service" \
  "$DELIGHT_STUB_STATE/active-delight-airplay.service"
cat >"$DELIGHT_STUB_STATE/ss.out" <<'SS'
UNCONN 0 0 0.0.0.0:319 0.0.0.0:*
UNCONN 0 0 0.0.0.0:320 0.0.0.0:*
SS
: >"$DELIGHT_STUB_STATE/ufw-status"
while IFS=$'\t' read -r proto ports; do
  for cidr in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
    printf '%s ALLOW IN %s # omarchy-delight:airplay\n' "$ports/$proto" "$cidr" >>"$DELIGHT_STUB_STATE/ufw-status"
  done
done < <(jq -r '.firewall[] | [.proto, .ports] | @tsv' "$MODULE_DIR/module.json")
ok "doctor reports a healthy receiver" bash -c '"$1" doctor >/dev/null' _ "$BIN"

rm -f "$DELIGHT_STUB_STATE/active-nqptp.service"
: >"$DELIGHT_STUB_STATE/ss.out"
rc=0
"$BIN" doctor >/dev/null || rc=$?
is "doctor reports inactive nqptp as fixable" "$rc" "1"

cat >"$DELIGHT_STUB_STATE/ss.out" <<'SS'
UNCONN 0 0 0.0.0.0:319 0.0.0.0:* users:(("ptp4l",pid=123,fd=3))
UNCONN 0 0 0.0.0.0:320 0.0.0.0:* users:(("ptp4l",pid=123,fd=4))
SS
rc=0
"$BIN" doctor >/dev/null || rc=$?
is "doctor reports another process holding PTP ports as action" "$rc" "3"

touch "$DELIGHT_STUB_STATE/active-nqptp.service"
rm -f "$DELIGHT_STUB_STATE/no-ap2"
: >"$DELIGHT_STUB_STATE/ss.out"
touch "$DELIGHT_STUB_STATE/no-ap2"
rc=0
"$BIN" doctor >/dev/null || rc=$?
is "doctor reports missing AirPlay 2 support as unsupported" "$rc" "2"
rm -f "$DELIGHT_STUB_STATE/no-ap2"

printf '%s\n' '7000/tcp ALLOW IN Anywhere # omarchy-delight:airplay' >>"$DELIGHT_STUB_STATE/ufw-status"
rc=0
"$BIN" doctor >/dev/null || rc=$?
is "doctor rejects public firewall rules" "$rc" "1"
sed -i '/Anywhere.*omarchy-delight:airplay/d' "$DELIGHT_STUB_STATE/ufw-status"

touch "$DELIGHT_STUB_STATE/active-shairport-sync.service"
rc=0
"$BIN" doctor >/dev/null || rc=$?
is "doctor rejects an active packaged system receiver" "$rc" "1"
rm -f "$DELIGHT_STUB_STATE/active-shairport-sync.service"

"$BIN" uninstall
ok "uninstall disables nqptp enabled by Delight" grep -F 'systemctl disable --now nqptp.service' "$DELIGHT_STUB_LOG"
ok "uninstall removes packages Delight added" grep -F 'pacman -Rns --noconfirm -- shairport-sync nqptp' "$DELIGHT_STUB_LOG"
not_ok "uninstall removes the generated configuration" test -e "$HOME/.config/omarchy-delight/airplay/shairport-sync.conf"
not_ok "uninstall removes the AirPlay config directory" test -e "$HOME/.config/omarchy-delight/airplay"
not_ok "uninstall removes module state" test -e "$HOME/.local/state/omarchy-delight/airplay"
not_ok "uninstall removes the status file" test -e "$XDG_RUNTIME_DIR/omarchy-delight/status/airplay.json"
not_ok "uninstall removes runtime AirPlay state" test -e "$XDG_RUNTIME_DIR/omarchy-delight/airplay"
has_revoked_rule() {
  grep -F "ufw delete allow in proto $1" "$DELIGHT_STUB_LOG" | grep -F "port $2"
}
for ports_proto in \
  "udp 319:320" "tcp 3689" "udp 5353" "tcp 5353" "tcp 5000" \
  "tcp 7000" "udp 6000:6009" "udp 32768:60999" "tcp 32768:60999"; do
  read -r proto ports <<<"$ports_proto"
  ok "uninstall revokes firewall rule $proto $ports" has_revoked_rule "$proto" "$ports"
done

rm -f "$DELIGHT_STUB_LOG"
rm -rf "${DELIGHT_STUB_STATE:?}"/*
touch "$DELIGHT_STUB_STATE/unit-nqptp.service" \
  "$DELIGHT_STUB_STATE/pkg-shairport-sync" \
  "$DELIGHT_STUB_STATE/pkg-nqptp"
"$BIN" install
is "install does not claim pre-enabled nqptp" "$(jq -r '.flags.nqptpEnabled // "unset"' "$HOME/.local/state/omarchy-delight/airplay/installed.json")" "unset"
"$BIN" uninstall
not_ok "uninstall leaves pre-enabled nqptp enabled" grep -F 'systemctl disable --now nqptp.service' "$DELIGHT_STUB_LOG"

done_testing
