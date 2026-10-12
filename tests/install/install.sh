#!/bin/bash

# install.sh / uninstall.sh: idempotence, dry-run, byte-for-byte restore.

# shellcheck source=../lib/tap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/tap.sh"

sandbox
root=$(repo_copy)
cp -r "$root/templates/module" "$root/modules/example"

HYPR="$HOME/.config/hypr/hyprland.lua"
MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
mkdir -p "$(dirname -- "$HYPR")" "$(dirname -- "$MENU")"
printf -- '-- user config\nrequire("omarchy")\no.bind("SUPER + T", "Terminal", "exec", "foot")' >"$HYPR"
cp "$HYPR" "$SANDBOX/hyprland.orig"
printf '{\n  // mine\n  "personal": {"icon":"","label":"Personal"}\n}\n' >"$MENU"
cp "$MENU" "$SANDBOX/menu.orig"

delight_paths=("$HOME/.local/share/omarchy-delight" "$HOME/.local/bin/delight" "$HOME/.config/omarchy-delight"
  "$HOME/.local/state/omarchy-delight" "$XDG_RUNTIME_DIR/omarchy-delight" "$HOME/.config/omarchy/plugins/delight.control-center"
  "$HOME/.config/systemd/user/delight.target" "$HOME/.config/omarchy/hooks/theme-set.d/50-omarchy-delight")

jsonc_parse() {
  sed -E '/^[[:space:]]*\/\//d' "$1" | tr '\n' ' ' | sed -E 's/,[[:space:]]*([]}])/\1/g' | jq -e .
}

home_hash() {
  tree_hash "$HOME" "$XDG_RUNTIME_DIR"
}

# Dry run.
h0=$(home_hash)
dry1=$(DELIGHT_DRY_RUN=1 "$root/install.sh" 2>&1)
dry2=$(DELIGHT_DRY_RUN=1 "$root/install.sh" 2>&1)
is "dry-run install twice gives identical output" "$dry1" "$dry2"
is "dry-run install changes nothing" "$(home_hash)" "$h0"
ok "dry-run prints DRY actions" grep -q '^DRY: ' <<<"$dry1"
ok "dry-run never calls a stubbed command for side effects" test ! -s "$DELIGHT_STUB_LOG" -o -z "$(grep -vE '^(omarchy plugin list|pacman -Q|systemctl --user is-enabled)' "$DELIGHT_STUB_LOG")"

# Real install, twice.
ok "install.sh succeeds" "$root/install.sh"
h1=$(home_hash)
out2=$("$root/install.sh" 2>&1)
is "second install changes nothing" "$(home_hash)" "$h1"
out3=$("$root/install.sh" 2>&1)
is "repeated installs give identical output" "$out3" "$out2"
is "dry-run after install has nothing to do" "$(DELIGHT_DRY_RUN=1 "$root/install.sh" 2>&1 | grep -c '^DRY: ')" "0"

is "delight resolves on PATH" "$(command -v delight)" "$HOME/.local/bin/delight"
is "share dir links to the checkout" "$(readlink -f "$HOME/.local/share/omarchy-delight")" "$root"
ok "config.json matches schema" schema_valid "$DELIGHT_TEST_REPO/schema/config.schema.json" "$HOME/.config/omarchy-delight/config.json"
is "delight status --json prints []" "$(delight status --json)" "[]"
ok "delight.target installed" test -f "$HOME/.config/systemd/user/delight.target"
ok "delight.target enabled" grep -qx 'systemctl --user enable delight.target' "$DELIGHT_STUB_LOG"
ok "control center plugin installed" test -f "$HOME/.config/omarchy/plugins/delight.control-center/manifest.json"
ok "control center bundles qml/Delight" test -f "$HOME/.config/omarchy/plugins/delight.control-center/Delight/qmldir"
is "control center plugin has no symlinks" "$(find "$HOME/.config/omarchy/plugins/delight.control-center" -type l | wc -l)" "0"
ok "control center plugin enabled" grep -qx 'omarchy plugin enable delight.control-center' "$DELIGHT_STUB_LOG"
is "plugin enabled only once" "$(grep -cx 'omarchy plugin enable delight.control-center' "$DELIGHT_STUB_LOG")" "1"
ok "hyprland.lua loads the generated file" grep -q 'pcall(dofile, os.getenv("HOME") .. "/.config/omarchy-delight/hypr.lua")' "$HYPR"
ok "generated hypr.lua exists" test -f "$HOME/.config/omarchy-delight/hypr.lua"
ok "menu file still parses" jsonc_parse "$MENU"
is "menu keeps the user's entry" "$(jsonc_parse "$MENU" | jq -r '.personal.label')" "Personal"
is "menu has the Control Center entry" "$(jsonc_parse "$MENU" | jq -r '."delight.control-center".action')" "delight ui toggle delight.control-center"
ok "theme hook installed and executable" test -x "$HOME/.config/omarchy/hooks/theme-set.d/50-omarchy-delight"
ok "theme hook runs" "$HOME/.config/omarchy/hooks/theme-set.d/50-omarchy-delight" catppuccin

# A module on top.
ok "delight example install" delight example install
is "delight list shows example installed" "$(delight list | awk -F'\t' '$1 == "example" {print $2}')" "installed"
is "status lists the module" "$(delight status --json | jq -r '.[].id')" "example"
is "menu gains module entries" "$(jsonc_parse "$MENU" | jq -r '."delight.example.toggle".action')" "delight example toggle"
ok "delight example toggle" delight example toggle
is "toggle turned it on" "$(delight status --json | jq -r '.[0].state')" "on"
is "config records it" "$(delight config get example.enabled)" "true"
ok "delight config set" delight config set example.label '"Desk"'
is "delight config get" "$(delight config get example.label)" "Desk"
not_ok "unknown module fails" delight nosuch status
is "share-targets aggregates to []" "$(delight share-targets --json)" "[]"
is "devices aggregates to []" "$(delight devices --json)" "[]"
ok "delight doctor" delight doctor
ok "delight ui summon" delight ui summon delight.control-center
ok "summon reaches omarchy-shell" grep -q '^omarchy-shell shell summon delight.control-center {}' "$DELIGHT_STUB_LOG"
not_ok "ui summon refuses non-delight ids" delight ui summon omarchy.menu

# Uninstall.
dry_un=$(DELIGHT_DRY_RUN=1 "$root/uninstall.sh" 2>&1)
is "dry-run uninstall changes nothing" "$(home_hash)" "$(home_hash)"
ok "dry-run uninstall prints actions" grep -q '^DRY: ' <<<"$dry_un"
ok "uninstall.sh succeeds" "$root/uninstall.sh"
ok "hyprland.lua restored byte-for-byte" cmp "$HYPR" "$SANDBOX/hyprland.orig"
ok "menu restored byte-for-byte" cmp "$MENU" "$SANDBOX/menu.orig"
for path in "${delight_paths[@]}"; do
  not_ok "removed ${path#"$HOME"/}" test -e "$path" -o -L "$path"
done
is "no Delight markers left in HOME" "$(grep -rl 'omarchy-delight >>>' "$HOME" 2>/dev/null | wc -l)" "0"
ok "plugin disabled" grep -qx 'omarchy plugin disable delight.control-center' "$DELIGHT_STUB_LOG"
ok "uninstall.sh is idempotent" "$root/uninstall.sh"

# Fresh HOME without a menu file: the file we create is removed again.
rm -rf "$HOME" && mkdir -p "$(dirname -- "$HYPR")" && cp "$SANDBOX/hyprland.orig" "$HYPR"
ok "install without an existing menu file" "$root/install.sh"
ok "menu file created" jsonc_parse "$MENU"
ok "uninstall" "$root/uninstall.sh"
not_ok "created menu file removed" test -e "$MENU"
ok "hyprland.lua restored again" cmp "$HYPR" "$SANDBOX/hyprland.orig"

# User edits after install survive uninstall.
ok "reinstall" "$root/install.sh"
printf '\n-- added later\n' >>"$HYPR"
ok "uninstall after user edit" "$root/uninstall.sh"
is "user edit kept, block removed" "$(
  grep -c 'omarchy-delight' "$HYPR"
  grep -c 'added later' "$HYPR"
)" $'0\n1'

done_testing
