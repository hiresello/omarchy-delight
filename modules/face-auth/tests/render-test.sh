#!/bin/bash

# Golden output of the config generator, and rejection of policies that would
# weaken the password.

source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"

ROOT="$DELIGHT_TEST_REPO/modules/face-auth"
# shellcheck source=../lib/policy.sh
source "$ROOT/lib/policy.sh"
# shellcheck source=../lib/pamcheck.sh
source "$ROOT/lib/pamcheck.sh"
# shellcheck source=../lib/render.sh
source "$ROOT/lib/render.sh"

T="$ROOT/templates"
defaults="$ROOT/defaults.json"

norm() {
  face_auth_policy_normalize <<<"$(face_auth_policy_merge "$defaults" "$1")"
}

policy=$(norm '{}')
stage=$(mktemp -d)
ok "default policy renders" face_auth_render_tree "$policy" "$stage"
ok "hyprlock matches the template" cmp -s "$stage/pam.d/hyprlock" "$T/default/pam.d/hyprlock"
ok "gate matches the template" cmp -s "$stage/lib/face-auth-gate" "$T/default/lib/face-auth-gate"
ok "stamp matches the template" cmp -s "$stage/lib/face-auth-stamp" "$T/default/lib/face-auth-stamp"
ok "sleep hook matches the template" cmp -s "$stage/system-sleep/omarchy-delight-face-auth" "$T/default/system-sleep/omarchy-delight-face-auth"
ok "rollback script matches the template" cmp -s "$stage/sbin/delight-face-auth-disable" "$T/default/sbin/delight-face-auth-disable"
ok "recommendations match the template" cmp -s "$stage/recommendations.txt" "$T/default/recommendations.txt"
not_ok "sudo is off by default" test -f "$stage/pam.d/sudo"
rm -rf -- "$stage"

sudo_policy=$(jq -c '.scope.sudo = true' <<<"$policy")
stage=$(mktemp -d)
ok "sudo policy renders" face_auth_render_tree "$sudo_policy" "$stage"
ok "sudo pam matches the template" cmp -s "$stage/pam.d/sudo" "$T/sudo/pam.d/sudo"
ok "sudo stack names the sudo gate" grep -q 'face-auth-gate sudo' "$stage/pam.d/sudo"
rm -rf -- "$stage"

reject() {
  local desc="$1" overlay="$2" reason="$3" err
  err=$(
    {
      face_auth_policy_normalize <<<"$(face_auth_policy_merge "$defaults" "$overlay")" >/dev/null
    } 2>&1
  ) || true
  ok "$desc" grep -q "$reason" <<<"$err"
}

reject "login is not a face service" '{"scope":{"login":true}}' 'policy: scope-service'
reject "sudo cache of 0 is rejected" '{"sudo_cache_seconds":0}' 'policy: sudo-cache'
reject "sudo cache over 15 minutes is rejected" '{"sudo_cache_seconds":901}' 'policy: sudo-cache'
reject "negative suspend limit is rejected" '{"suspend_max_seconds":-1}' 'policy: suspend'
reject "deny below 3 is rejected" '{"deny":2}' 'policy: deny'
reject "deny above 10 is rejected" '{"deny":11}' 'policy: deny'
reject "/dev/videoN is rejected" '{"device_path":"/dev/video0"}' 'policy: device-path'
reject "unknown policy key is rejected" '{"sole_factor":true}' 'policy: unknown'

by_path=$(norm '{"device_path":"/dev/v4l/by-path/pci-0000:00:00.0-platform-cam"}')
ok "stable by-path device is accepted" jq -e '.device_path | startswith("/dev/v4l/by-path/")' <<<"$by_path"
stage=$(mktemp -d)
ok "by-path policy renders" face_auth_render_tree "$by_path" "$stage"
ok "recommendations name that device" grep -q 'pci-0000:00:00.0-platform-cam' "$stage/recommendations.txt"
rm -rf -- "$stage"

both_off=$(norm '{"scope":{"hyprlock":false,"sudo":false}}')
stage=$(mktemp -d)
ok "no-service policy still renders helpers" face_auth_render_tree "$both_off" "$stage"
not_ok "no-service policy writes no pam file" test -f "$stage/pam.d/hyprlock"
rm -rf -- "$stage"

done_testing
