#!/bin/bash

# Unit tests for lib/delight helpers.

# shellcheck source=../lib/tap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/tap.sh"

sandbox
DELIGHT_ROOT=$(repo_copy)
cp -r "$DELIGHT_ROOT/templates/module" "$DELIGHT_ROOT/modules/example"
# shellcheck source=../../lib/delight/delight.sh
source "$DELIGHT_ROOT/lib/delight/delight.sh"
set +e

# config
is "config default comes from defaults.json" "$(delight_config_get example enabled)" "false"
not_ok "missing config key fails" delight_config_get example nope
delight_config_set example enabled true
is "config set bool" "$(delight_config_get example enabled)" "true"
delight_config_set example nested.name "My Desk"
is "config set nested string" "$(delight_config_get example nested.name)" "My Desk"
delight_config_set other enabled false
is "modules keep separate keys" "$(jq -c '.modules | keys' "$DELIGHT_CONFIG_FILE")" '["example","other"]'
delight_config_unset_module other
is "unset module removes its key only" "$(jq -c '.modules | keys' "$DELIGHT_CONFIG_FILE")" '["example"]'
is "dry-run config set prints DRY" "$(DELIGHT_DRY_RUN=1 delight_config_set example enabled false | cut -c1-4)" "DRY:"

# state
delight_state_add example packages '{"name":"foo","source":"repo"}'
delight_state_add example packages '{"name":"foo","source":"repo"}'
is "state add is idempotent" "$(delight_state_list example packages | wc -l)" "1"
is "state owners" "$(delight_state_owners packages '.name == "foo"')" "example"
delight_state_del example packages '{"name":"foo","source":"repo"}'
is "state del" "$(delight_state_list example packages | wc -l)" "0"

# packages
is "pkg_add dry-run prints the install" "$(DELIGHT_DRY_RUN=1 delight_pkg_add example repo foo 2>/dev/null)" "DRY: omarchy-pkg-add foo"
delight_pkg_add example repo foo 2>/dev/null
ok "pkg_add records added packages" grep -q '"foo"' "$(delight_state_file example)"
touch "$DELIGHT_STUB_STATE/pkg-bar"
delight_pkg_add example repo bar 2>/dev/null
not_ok "pkg_add does not record pre-installed packages" grep -q '"bar"' "$(delight_state_file example)"
touch "$DELIGHT_STUB_STATE/pkg-foo"
delight_state_add other packages '{"name":"foo","source":"repo"}'
delight_pkg_remove example 2>/dev/null
not_ok "pkg_remove keeps packages another module recorded" grep -q 'pacman -Rns' "$DELIGHT_STUB_LOG"
delight_pkg_remove other 2>/dev/null
ok "pkg_remove removes the last owner's packages" grep -q 'pacman -Rns --noconfirm -- foo' "$DELIGHT_STUB_LOG"
not_ok "pkg_add rejects unknown sources" bash -c "source '$DELIGHT_ROOT/lib/delight/delight.sh'; delight_pkg_add example npm x"

# firewall
rules=$(DELIGHT_DRY_RUN=1 delight_ufw_allow example tcp 7000)
is "ufw_allow opens one rule per private CIDR" "$(grep -c 'omarchy-delight:example' <<<"$rules")" "3"
ok "ufw_allow covers 192.168.0.0/16" grep -q '192.168.0.0/16' <<<"$rules"
not_ok "ufw_allow never opens to any source" grep -q 'from any' <<<"$rules"
delight_ufw_allow example udp 5353
is "ufw_allow records the rule" "$(delight_state_list example firewall)" '{"proto":"udp","ports":"5353","tailscale":false}'
delight_ufw_revoke example
is "ufw_revoke deletes each rule" "$(grep -c '^ufw delete allow in proto udp' "$DELIGHT_STUB_LOG")" "3"
is "ufw_revoke clears the record" "$(delight_state_list example firewall | wc -l)" "0"

# units
printf '[Unit]\nPartOf=delight.target\n' >"$SANDBOX/delight-example.service"
printf '[Unit]\n' >"$SANDBOX/bad.service"
delight_unit_install example "$SANDBOX/delight-example.service"
ok "unit installed" test -f "$HOME/.config/systemd/user/delight-example.service"
not_ok "unit names are enforced" bash -c "source '$DELIGHT_ROOT/lib/delight/delight.sh'; delight_unit_install example '$SANDBOX/bad.service'"
delight_unit_remove example
not_ok "unit removed" test -f "$HOME/.config/systemd/user/delight-example.service"

# status
json=$(delight_status_json --id example --state unsupported --title Example --reason "No adapter")
ok "status_json output matches schema" schema_valid "$DELIGHT_TEST_REPO/schema/status.schema.json" <(printf '%s' "$json")
delight_status_write example "$json"
is "status_write writes the file" "$(jq -r .reason "$DELIGHT_STATUS_DIR/example.json")" "No adapter"
not_ok "status_write rejects a mismatched id" bash -c "source '$DELIGHT_ROOT/lib/delight/delight.sh'; delight_status_write other '$json'"

# blocks
f="$SANDBOX/file.lua"
printf 'a\nb' >"$f"
cp "$f" "$SANDBOX/file.orig"
delight_block_set_end "$f" "--" "x()"
delight_block_set_end "$f" "--" "y()"
is "block is replaced, not duplicated" "$(grep -c '>>> omarchy-delight >>>' "$f")" "1"
ok "block has the latest body" grep -qx 'y()' "$f"
delight_block_remove "$f"
ok "block removal restores bytes" cmp "$f" "$SANDBOX/file.orig"
j="$SANDBOX/menu.jsonc"
printf '{\n  "a": {"label":"A"}\n}\n' >"$j"
delight_block_set_jsonc "$j" '  "b": {"label":"B"},'
is "jsonc block lands inside the object" "$(sed -E '/^[[:space:]]*\/\//d' "$j" | tr -d '\n' | sed -E 's/,[[:space:]]*}/}/g' | jq -r '[.a.label, .b.label] | join(",")')" "A,B"

# dry-run plumbing
is "delight_run prints quoted argv" "$(DELIGHT_DRY_RUN=1 delight_run echo 'a b')" "DRY: echo a\\ b"
is "delight_write dry-run" "$(echo hi | DELIGHT_DRY_RUN=1 delight_write "$SANDBOX/new")" "DRY: write $SANDBOX/new"
not_ok "delight_write dry-run writes nothing" test -e "$SANDBOX/new"

# hardware probes never fail loudly
mkdir -p "$SANDBOX/sys/class/bluetooth/hci0"
ok "bluetooth detected via sysfs" env DELIGHT_SYSFS="$SANDBOX/sys" bash -c "source '$DELIGHT_ROOT/lib/delight/delight.sh'; delight_hw_bluetooth"
not_ok "no bluetooth without hci" env DELIGHT_SYSFS="$SANDBOX/none" bash -c "source '$DELIGHT_ROOT/lib/delight/delight.sh'; delight_hw_bluetooth"
not_ok "hyprland not running in tests" delight_hw_hyprland

done_testing
