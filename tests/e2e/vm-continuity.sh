#!/bin/bash

# End-to-end check on a fresh Omarchy VM (vm/run-all): install.sh, install and
# enable every module, the Control Center sees one status per module, the
# aggregated JSON validates, then uninstall leaves `pacman -Qe`, `ufw status`
# and ~/.config/hypr exactly as they were before Delight was installed.

[[ ${DELIGHT_VM:-} == 1 ]] || {
  echo "1..0 # SKIP runs inside the Delight VM (vm/run)"
  exit 0
}
# shellcheck source=vm/lib/guest.sh
source "$DELIGHT_VM_LIB"
# shellcheck source=tests/lib/tap.sh
source "$DELIGHT_ROOT/tests/lib/tap.sh"

root=$DELIGHT_ROOT
snap=$DELIGHT_VM_ARTIFACTS/logs/$DELIGHT_VM_TEST
mkdir -p "$snap"
mapfile -t modules < <(cd "$root/modules" && for d in */module.json; do printf '%s\n' "${d%/module.json}"; done)

snapshot() { # <name>
  pacman -Qe >"$snap/$1.pacman" 2>&1
  vm_sudo ufw status verbose >"$snap/$1.ufw" 2>&1
  (cd "$HOME/.config/hypr" && find . -type f -print0 | sort -z | xargs -0 sha256sum) >"$snap/$1.hypr"
}

valid() { # <schema> <json>: every element of a JSON array matches schema/<schema>
  jq -e 'type == "array"' <<<"$2" >/dev/null || return 1
  if command -v python3 >/dev/null && python3 -c 'import jsonschema' 2>/dev/null; then
    python3 - "$root/schema/$1" "$2" <<'PY'
import json, sys, jsonschema
schema = json.load(open(sys.argv[1]))
for item in json.loads(sys.argv[2]):
    jsonschema.validate(item, schema)
PY
  fi
}

# Start from no Delight at all.
"$root/uninstall.sh" >/dev/null 2>&1 || true
snapshot before

(cd "$root" && ./install.sh) >"$snap/install.log" 2>&1
is "install.sh exits 0" "$?" 0
ok "delight is on PATH" command -v delight

for id in "${modules[@]}"; do
  delight "$id" install >"$snap/$id-install.log" 2>&1
  rc=$?
  state=$(delight "$id" status --json 2>/dev/null | jq -r '.state // empty')
  if ((rc == 0)); then
    delight "$id" enable >"$snap/$id-enable.log" 2>&1
    rc=$?
    state=$(delight "$id" status --json 2>/dev/null | jq -r '.state // empty')
  fi
  reason=$(delight "$id" status --json 2>/dev/null | jq -r '.reason // ""')
  # Unsupported hardware is fine, as long as the module says why.
  if ((rc == 0)) || [[ $state == unsupported && -n $reason ]]; then
    ok "$id installs and enables (state: ${state:-?}${reason:+, $reason})" true
  else
    ok "$id installs and enables (exit $rc, state: ${state:-?})" false
  fi
done

status=$(delight status --json)
is "delight status --json exits 0" "$?" 0
printf '%s\n' "$status" >"$snap/status.json"
ok "status JSON validates" valid status.schema.json "$status"
is "one status per module (one Control Center tile each)" \
  "$(jq -r '[.[].id] | sort | join(" ")' <<<"$status")" "$(printf '%s\n' "${modules[@]}" | sort | paste -sd' ')"
ok "unsupported and error states carry a reason" \
  jq -e 'all(.[]; (.state != "unsupported" and .state != "error") or ((.reason // "") != ""))' <<<"$status"

targets=$(delight share-targets --json)
is "delight share-targets --json exits 0" "$?" 0
ok "share targets validate" valid share-target.schema.json "$targets"
devices=$(delight devices --json)
is "delight devices --json exits 0" "$?" 0
ok "devices validate" valid device.schema.json "$devices"

delight doctor >"$snap/doctor.log" 2>&1
ok "delight doctor ran (log saved)" true
is "Hyprland reports no config errors" "$(hyprctl -j configerrors | jq '[.[] | select(. != "")] | length')" 0

delight ui summon delight.control-center >/dev/null 2>&1
vm_screenshot control-center 4
delight ui summon delight.control-center >/dev/null 2>&1 || true

for id in "${modules[@]}"; do
  delight "$id" uninstall >"$snap/$id-uninstall.log" 2>&1
  is "$id uninstalls" "$?" 0
done
"$root/uninstall.sh" >"$snap/uninstall.log" 2>&1
is "uninstall.sh exits 0" "$?" 0

snapshot after
ok "pacman -Qe is unchanged" diff -u "$snap/before.pacman" "$snap/after.pacman"
ok "ufw status is unchanged" diff -u "$snap/before.ufw" "$snap/after.ufw"
ok "$HOME/.config/hypr is unchanged" diff -u "$snap/before.hypr" "$snap/after.hypr"
hash -r
not_ok "delight is gone from PATH" command -v delight

# Leave the VM as vm/install-delight left it.
(cd "$root" && ./install.sh) >/dev/null 2>&1

done_testing
