#!/bin/bash

# Sidecar unit + lifecycle tests with a stubbed hyprctl, systemctl and Sunshine API.

# shellcheck source=../../../tests/lib/tap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"
# shellcheck source=../lib/sidecar.sh
source "$DELIGHT_TEST_REPO/modules/sidecar/lib/sidecar.sh"

MOD="$DELIGHT_TEST_REPO/modules/sidecar"
BIN="$MOD/bin/delight-sidecar"

# --- Monitor-rule generation ---------------------------------------------

ipad=$(sidecar_mode ipad-11 landscape null)
is "preset resolves" "$(jq -c '[.width,.height,.refresh,.scale]' <<<"$ipad")" "[2388,1668,120,2]"
is "portrait swaps width/height" "$(sidecar_mode ipad-11 portrait null | jq -c '[.width,.height]')" "[1668,2388]"
is "custom preset" "$(sidecar_mode custom landscape '{"width":2000,"height":1200,"refresh":90,"scale":1.25}' | jq -c '[.width,.height,.refresh,.scale]')" "[2000,1200,90,1.25]"
not_ok "unknown preset fails" sidecar_mode nope landscape null
not_ok "custom without size fails" sidecar_mode custom landscape '{}'

mons='[{"name":"eDP-1","width":1920,"height":1080,"x":0,"y":0,"scale":1,"transform":0,"focused":false},
       {"name":"DP-1","width":2880,"height":1800,"x":1920,"y":0,"scale":2,"transform":0,"focused":true},
       {"name":"DELIGHT-SIDECAR","width":2388,"height":1668,"x":0,"y":0,"scale":2,"transform":0,"focused":false}]'
is "anchor is the focused physical monitor" "$(sidecar_anchor "$mons")" "DP-1"
is "anchor skips a focused sidecar" "$(sidecar_anchor "$(jq -c 'map(.focused = (.name == "DELIGHT-SIDECAR"))' <<<"$mons")")" "eDP-1"

is "right of 1080p" "$(sidecar_position "$mons" eDP-1 right "$ipad")" "1920x123"
is "left of 1080p" "$(sidecar_position "$mons" eDP-1 left "$ipad")" "-1194x123"
is "above 1080p" "$(sidecar_position "$mons" eDP-1 above "$ipad")" "363x-834"
is "below 1080p" "$(sidecar_position "$mons" eDP-1 below "$ipad")" "363x1080"
is "right of a scaled monitor uses logical size" "$(sidecar_position "$mons" DP-1 right "$ipad")" "3360x33"
rot='[{"name":"DP-2","width":1920,"height":1080,"x":0,"y":0,"scale":1,"transform":1}]'
is "rotated anchor swaps axes" "$(sidecar_position "$rot" DP-2 right "$ipad")" "1080x543"
not_ok "unknown anchor fails" sidecar_position "$mons" HDMI-9 right "$ipad"
not_ok "unknown side fails" sidecar_position "$mons" eDP-1 diagonal "$ipad"

is "lua monitor rule" "$(sidecar_monitor_lua "$ipad" 1920x123)" \
  'hl.monitor({ output = "DELIGHT-SIDECAR", mode = "2388x1668@120", position = "1920x123", scale = 2 })'
is "auto placement per side" "$(for s in right left above below; do sidecar_auto_position "$s"; done | paste -sd,)" \
  "auto-center-right,auto-center-left,auto-center-up,auto-center-down"
is "layout ignores the tablet" "$(sidecar_layout "$mons" | jq -c 'map(.name)')" '["DP-1","eDP-1"]'
is "lua rule keeps fractional scale" "$(sidecar_monitor_lua "$(sidecar_mode android-1200p landscape null)" 0x0)" \
  'hl.monitor({ output = "DELIGHT-SIDECAR", mode = "1920x1200@60", position = "0x0", scale = 1.5 })'
is "workspace move dispatcher" "$(sidecar_dispatch_move_workspace 3 eDP-1)" 'hl.dsp.workspace.move({ workspace = "3", monitor = "eDP-1" })'
is "lua strings are escaped" "$(sidecar_dispatch_focus_monitor 'a"b')" 'hl.dsp.focus({ monitor = "a\"b" })'

# --- Sunshine config rendering --------------------------------------------

is "sunshine overrides" "$(sidecar_sunshine_args wlr "")" $'output_name=DELIGHT-SIDECAR\ncapture=wlr'
is "sunshine overrides with encoder" "$(sidecar_sunshine_args wlr vaapi)" $'output_name=DELIGHT-SIDECAR\ncapture=wlr\nencoder=vaapi'
is "sunshine overrides, auto capture" "$(sidecar_sunshine_args "" "")" "output_name=DELIGHT-SIDECAR"
pending='{"pairings":[{"id":"aa","name":"old"},{"id":"bb","name":"iPad"}]}'
is "pin payload uses newest pairing id" "$(sidecar_pin_payload "$pending" 1234 iPad)" '{"pairing_id":"bb","pin":"1234","name":"iPad"}'
is "legacy pin payload" "$(sidecar_pin_payload null 1234 iPad)" '{"pin":"1234","name":"iPad"}'
ok "valid pin" sidecar_valid_pin 0420
not_ok "pin must be 4 digits" sidecar_valid_pin 12a4

# --- Lifecycle with stubs -------------------------------------------------

sandbox
export PATH="$MOD/tests/stubs:$PATH"
export HYPRLAND_INSTANCE_SIGNATURE=test
FAKEBIN="$SANDBOX/fakebin"
mkdir -p "$FAKEBIN"
export PATH="$FAKEBIN:$PATH"

fake_sunshine() {
  cat >"$FAKEBIN/sunshine" <<'SH'
#!/bin/bash
printf 'sunshine %s\n' "$*" >>"$DELIGHT_STUB_LOG"
if [[ ${1:-} == "--creds" ]]; then
  mkdir -p "$HOME/.config/sunshine"
  printf '{"username":"%s"}\n' "$2" >"$HOME/.config/sunshine/sunshine_state.json"
fi
SH
  chmod +x "$FAKEBIN/sunshine"
}

printf '#!/bin/bash\nprintf "qrencode %%s\\n" "$*" >>"$DELIGHT_STUB_LOG"\n' >"$FAKEBIN/qrencode"
chmod +x "$FAKEBIN/qrencode"

others() {
  hyprctl monitors -j | jq -c '[.[] | select(.name != "DELIGHT-SIDECAR")]'
}

sidecar_mon() {
  hyprctl monitors -j | jq -c '.[] | select(.name == "DELIGHT-SIDECAR") | [.width, .height, .refreshRate, .scale, .x, .y]'
}

ok "fresh install" "$BIN" install
ok "sunshine installed via package helper" grep -q '^omarchy-pkg-add sunshine' "$DELIGHT_STUB_LOG"
ok "firewall opened for Moonlight" grep -q 'ufw allow in proto udp from 192.168.0.0/16 to any port 47998 comment omarchy-delight:sidecar' "$DELIGHT_STUB_LOG"
is "sunshine recorded as Delight-owned" "$(jq -c '[.packages[].name] | index("sunshine") != null' "$HOME/.local/state/omarchy-delight/sidecar/installed.json")" "true"
ok "plugin staged" test -f "$HOME/.config/omarchy/plugins/delight.sidecar/SidecarPanel.qml"
touch "$DELIGHT_STUB_STATE/pkg-sunshine"
fake_sunshine
ok "install again (bootstraps Sunshine login)" "$BIN" install
ok "credentials stored 0600" test "$(stat -c %a "$HOME/.local/state/omarchy-delight/sidecar/sunshine-credentials")" = 600
is "status off" "$("$BIN" status --json | jq -r .state)" "off"

touch "$DELIGHT_STUB_STATE/active-sunshine.service"
before=$(others)
ok "start" "$BIN" start
is "DELIGHT-SIDECAR at the requested mode, right of the focused monitor" "$(sidecar_mon)" "[2388,1668,120,2,1440,33]"
is "other monitors unchanged by start" "$(others | jq -c 'map(del(.focused))')" "$(jq -c 'map(del(.focused))' <<<"$before")"
is "focus stays on the anchor" "$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')" "eDP-1"
is "status on" "$("$BIN" status --json | jq -r .state)" "on"
is "status subtitle" "$("$BIN" status --json | jq -r .subtitle)" "iPad Pro 11\", right of eDP-1"
ok "status file published" grep -q '"state":"on"' "$XDG_RUNTIME_DIR/omarchy-delight/status/sidecar.json"
not_ok "user's sunshine.service parked" test -f "$DELIGHT_STUB_STATE/active-sunshine.service"
ok "sidecar unit running" test -f "$DELIGHT_STUB_STATE/active-delight-sidecar.service"
is "sunshine args rendered" "$(cat "$XDG_RUNTIME_DIR/omarchy-delight/sidecar/sunshine.args")" $'output_name=DELIGHT-SIDECAR\ncapture=wlr'
ok "reload-safe rule written" grep -q 'output = "DELIGHT-SIDECAR"' "$XDG_RUNTIME_DIR/omarchy-delight/sidecar/monitor.lua"
ok "start is idempotent" "$BIN" start
is "still one sidecar" "$(hyprctl monitors -j | jq '[.[] | select(.name == "DELIGHT-SIDECAR")] | length')" "1"

ok "arrange above while running" "$BIN" set arrangement above
is "moved above" "$(sidecar_mon)" "[2388,1668,120,2,123,-834]"
ok "preset change while running" "$BIN" set preset android-1200p
is "new mode applied live" "$(sidecar_mon)" "[1920,1200,60,1.5,80,-800]"
not_ok "bad arrangement rejected" "$BIN" set arrangement diagonal
not_ok "bad preset rejected" "$BIN" set preset nope

ws=$(hyprctl workspaces -j | jq -r '.[] | select(.monitor == "DELIGHT-SIDECAR") | .name')
ok "toggle stops" "$BIN" toggle
is "DELIGHT-SIDECAR removed" "$(hyprctl monitors -j | jq '[.[] | select(.name == "DELIGHT-SIDECAR")] | length')" "0"
is "other monitors unchanged by stop" "$(others | jq -c 'map(del(.focused))')" "$(jq -c 'map(del(.focused))' <<<"$before")"
is "sidecar workspace moved back to the anchor" "$(hyprctl workspaces -j | jq -r --arg w "$ws" '.[] | select(.name == $w) | .monitor')" "eDP-1"
ok "workspace moved explicitly before removal" grep -q "hl.dsp.workspace.move({ workspace = \"$ws\", monitor = \"eDP-1\" })" "$DELIGHT_STUB_LOG"
ok "user's sunshine.service restored" test -f "$DELIGHT_STUB_STATE/active-sunshine.service"
not_ok "sidecar unit stopped" test -f "$DELIGHT_STUB_STATE/active-delight-sidecar.service"
not_ok "runtime rule removed" test -e "$XDG_RUNTIME_DIR/omarchy-delight/sidecar/monitor.lua"
is "status off after stop" "$("$BIN" status --json | jq -r .state)" "off"
ok "stop is idempotent" "$BIN" stop

# Omarchy's catch-all rule positions monitors "auto"; Hyprland lays those out
# after explicit ones, so the tablet must not be given an explicit spot then.
cp "$DELIGHT_STUB_STATE/hypr.json" "$SANDBOX/hypr.json.saved"
jq '.monitors = [.monitors[0] | .auto = "auto"] | .workspaces |= map(.monitor = "eDP-1")' \
  "$SANDBOX/hypr.json.saved" >"$DELIGHT_STUB_STATE/hypr.json"
auto_before=$(others)
ok "start next to an auto-positioned monitor" "$BIN" start
is "auto monitor not shoved by an explicit tablet position" "$(others)" "$auto_before"
is "tablet placed above by Hyprland" "$(sidecar_mon)" "[1920,1200,60,1.5,80,-800]"
ok "falls back to auto placement" grep -q 'position = "auto-center-up"' "$XDG_RUNTIME_DIR/omarchy-delight/sidecar/monitor.lua"
ok "arrange left while running" "$BIN" set arrangement left
is "auto monitor still in place" "$(others)" "$auto_before"
is "tablet left of the auto monitor" "$(sidecar_mon)" "[1920,1200,60,1.5,-1280,50]"
ok "stop" "$BIN" stop
is "auto monitor unchanged after stop" "$(others)" "$auto_before"
not_ok "placement memo cleared" test -e "$XDG_RUNTIME_DIR/omarchy-delight/sidecar/placement"
cp "$SANDBOX/hypr.json.saved" "$DELIGHT_STUB_STATE/hypr.json"
ok "back to the right" "$BIN" set arrangement right
ok "back to the iPad preset" "$BIN" set preset ipad-11

rm -f "$DELIGHT_STUB_STATE/active-sunshine.service"
touch "$DELIGHT_STUB_STATE/stray-sunshine"
ok "toggle starts (stray sunshine)" "$BIN" toggle
not_ok "stray sunshine stopped" test -f "$DELIGHT_STUB_STATE/stray-sunshine"
ok "stop" "$BIN" stop
ok "stray sunshine relaunched" grep -q '^setsid -f .*sunshine' "$DELIGHT_STUB_LOG"

: >"$DELIGHT_STUB_LOG"
ok "dry-run start" env DELIGHT_DRY_RUN=1 "$BIN" start
is "dry-run creates nothing" "$(hyprctl monitors -j | jq '[.[] | select(.name == "DELIGHT-SIDECAR")] | length')" "0"
not_ok "dry-run never calls output create" grep -q '^hyprctl output create' "$DELIGHT_STUB_LOG"

# Pairing.
ok "pair with PIN" "$BIN" pair 1234
ok "POST carries pairing_id" grep -q 'curl POST https://localhost:47990/api/pin user=delight {"pairing_id":"0123456789abcdef0123456789abcdef","pin":"1234","name":"iPad"}' "$DELIGHT_STUB_LOG"
not_ok "password never on argv" grep -q "$(jq -r .password "$HOME/.local/state/omarchy-delight/sidecar/sunshine-credentials")" "$DELIGHT_STUB_LOG"
not_ok "wrong PIN fails" "$BIN" pair 9999
not_ok "malformed PIN rejected" "$BIN" pair 12345
ok "legacy Sunshine pairing" env SIDECAR_STUB_LEGACY=1 "$BIN" pair 1234 Tab
ok "legacy POST has no pairing_id" grep -q 'curl POST .*{"pin":"1234","name":"Tab"}' "$DELIGHT_STUB_LOG"
ok "credentials from stdin" bash -c "printf 'secret\n' | '$BIN' credentials me"
is "credentials saved" "$(jq -r .user "$HOME/.local/state/omarchy-delight/sidecar/sunshine-credentials")" "me"

# Hotkey + Deskreen.
ok "set hotkey" "$BIN" set hotkey "SUPER + CTRL + ALT + T"
is "hotkey file for hypr.lua" "$(cat "$HOME/.local/state/omarchy-delight/sidecar/hotkey")" "SUPER + CTRL + ALT + T"
ok "clear hotkey" "$BIN" set hotkey ""
not_ok "hotkey file removed" test -e "$HOME/.local/state/omarchy-delight/sidecar/hotkey"
ok "deskreen backend" "$BIN" set backend deskreen
is "deskreen labelled view-only" "$("$BIN" status --json | jq -r .subtitle)" "iPad Pro 11\", right (view-only)"
ok "info --json" bash -c "'$BIN' info --json | jq -e '.config.backend == \"deskreen\" and (.deskreenUrl | startswith(\"http://\")) and (.presets | length) > 3'"
ok "back to sunshine" "$BIN" set backend sunshine
ok "start for info" "$BIN" start
ok "info --json lists pending pairings" bash -c "'$BIN' info --json | jq -e '.pending | length == 1'"
ok "info --json survives a failing pairing API" bash -c "SIDECAR_STUB_PIN_FAIL=1 '$BIN' info --json | jq -e '.pending == []'"
ok "info --json offers the custom preset" bash -c "'$BIN' info --json | jq -e 'any(.presets[]; .id == \"custom\" and .label == \"Custom 2388x1668\")'"
ok "stop after info" "$BIN" stop

# Doctor.
"$BIN" doctor >/dev/null 2>&1
is "doctor ok with Sunshine + credentials" "$?" "0"
mv "$HOME/.local/state/omarchy-delight/sidecar/sunshine-credentials" "$SANDBOX/creds"
"$BIN" doctor >/dev/null 2>&1
is "doctor needs user action without credentials" "$?" "3"
mv "$SANDBOX/creds" "$HOME/.local/state/omarchy-delight/sidecar/sunshine-credentials"
env -u HYPRLAND_INSTANCE_SIGNATURE "$BIN" doctor >/dev/null 2>&1
is "doctor unsupported without Hyprland" "$?" "2"
is "status unsupported carries a reason" "$(env -u HYPRLAND_INSTANCE_SIGNATURE "$BIN" status --json | jq -r '.state + ":" + (.reason // "")')" "unsupported:Needs a running Hyprland session"

# Uninstall a Delight-installed Sunshine.
ok "uninstall" "$BIN" uninstall
ok "Delight-installed sunshine removed" grep -Eq 'pacman -R.* sunshine' "$DELIGHT_STUB_LOG"

# Pre-existing Sunshine is left alone.
rm -rf "$HOME/.local/state/omarchy-delight" "$HOME/.config/sunshine"
: >"$DELIGHT_STUB_LOG"
mkdir -p "$HOME/.config/sunshine"
echo '{"username":"me"}' >"$HOME/.config/sunshine/sunshine_state.json"
echo 'output_name=0' >"$HOME/.config/sunshine/sunshine.conf"
conf_before=$(tree_hash "$HOME/.config/sunshine")
touch "$DELIGHT_STUB_STATE/active-sunshine.service"
ok "install over existing Sunshine" "$BIN" install
not_ok "no sunshine package install" grep -q 'pkg-add sunshine\|aur-add sunshine' "$DELIGHT_STUB_LOG"
not_ok "no firewall changes" grep -q '^ufw' "$DELIGHT_STUB_LOG"
not_ok "no credentials generated" grep -q '^sunshine --creds' "$DELIGHT_STUB_LOG"
ok "start/stop cycle" bash -c "'$BIN' start && '$BIN' stop"
ok "uninstall" "$BIN" uninstall
not_ok "pre-existing sunshine kept" grep -Eq 'pacman -R.* sunshine' "$DELIGHT_STUB_LOG"
is "sunshine config untouched" "$(tree_hash "$HOME/.config/sunshine")" "$conf_before"
ok "user's sunshine.service running again" test -f "$DELIGHT_STUB_STATE/active-sunshine.service"

done_testing
