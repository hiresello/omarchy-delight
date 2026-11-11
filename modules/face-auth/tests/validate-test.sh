#!/bin/bash

# The validator must reject stacks that skip the password or can lock a
# console out, and apply must refuse those stacks without touching PAM.

source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"

ROOT="$DELIGHT_TEST_REPO/modules/face-auth"
# shellcheck source=../lib/policy.sh
source "$ROOT/lib/policy.sh"
# shellcheck source=../lib/store.sh
source "$ROOT/lib/store.sh"
# shellcheck source=../lib/pamcheck.sh
source "$ROOT/lib/pamcheck.sh"
# shellcheck source=../lib/render.sh
source "$ROOT/lib/render.sh"
# shellcheck source=../lib/apply.sh
source "$ROOT/lib/apply.sh"

policy=$(face_auth_policy_normalize <<<"$(face_auth_policy_merge "$ROOT/defaults.json" '{}')")
stage=$(mktemp -d)
face_auth_render_tree "$policy" "$stage"
good="$stage/pam.d/hyprlock"

ok "generated hyprlock is safe" face_auth_validate_pam_file "$good" "$policy" hyprlock
not_ok "login is rejected even with the safe text" face_auth_validate_pam_file "$good" "$policy" login
not_ok "polkit is rejected" face_auth_validate_pam_file "$good" "$policy" polkit-1
not_ok "system-auth is rejected" face_auth_validate_pam_file "$good" "$policy" system-auth
not_ok "sshd is rejected" face_auth_validate_pam_file "$good" "$policy" sshd

mutate() {
  local desc="$1" expr="$2" needle="$3" file
  file=$(mktemp)
  sed "$expr" "$good" >"$file"
  err=$(
    {
      face_auth_validate_pam_file "$file" "$policy" hyprlock >/dev/null
    } 2>&1
  ) || true
  ok "$desc" grep -q "$needle" <<<"$err"
  rm -f -- "$file"
}

mutate "sufficient howdy is rejected" 's/\[success=4 default=ignore\]/sufficient/' 'shape:'
mutate "nullok is rejected" 's/try_first_pass/try_first_pass nullok/' 'forbidden: nullok'
mutate "pam_permit is rejected" 's/pam_deny.so/pam_permit.so/' 'forbidden: pam_permit'
mutate "even_deny_root is rejected" 's/preauth silent/preauth even_deny_root silent/' 'forbidden: even_deny_root'
mutate "native workaround is rejected" 's/pam_howdy.so/pam_howdy.so workaround=native/' 'forbidden: workaround=native'
mutate "including system-auth is rejected" '$ a auth include system-auth' 'forbidden: include'
mutate "dropping the gate is rejected" '/face-auth-gate/d' 'shape:'
mutate "a wrong faillock deny is rejected" 's/deny=5/deny=99/g' 'faillock:'

# Apply / rollback against a fake root. Mount fixture: the whole tree is LUKS.
root=$(mktemp -d)
mounts=$(mktemp)
printf '%s\n' '/dev/mapper/cryptroot / ext4 rw,relatime 0 0' >"$mounts"
mkdir -p -- "$root/etc/pam.d"
printf '%s\n' 'ORIGINAL-HYPRLOCK' >"$root/etc/pam.d/hyprlock"
export FACE_AUTH_ROOT=$root

before=$(tree_hash "$root")
ok "dry-run exits 0" face_auth_apply_policy "$policy" "$mounts" --dry-run
is "dry-run does not write" "$(tree_hash "$root")" "$before"

mkdir -p -- "$root/etc/howdy/models"
printf 'template' >"$root/etc/howdy/models/juan.dat"
chmod 0644 -- "$root/etc/howdy/models/juan.dat"

plain=$(mktemp)
printf '%s\n' '/dev/sda2 / ext4 rw 0 0' >"$plain"
not_ok "unencrypted mount is refused" face_auth_apply_policy "$policy" "$plain"
is "refused apply leaves the original pam file" "$(cat "$root/etc/pam.d/hyprlock")" "ORIGINAL-HYPRLOCK"

ok "apply on an encrypted mount" face_auth_apply_policy "$policy" "$mounts"
is "model file is tightened to 0600" "$(stat -c %a "$root/etc/howdy/models/juan.dat")" "600"
is "model directory is 0700" "$(stat -c %a "$root/etc/howdy/models")" "700"
ok "installed hyprlock validates" face_auth_validate_pam_file "$root/etc/pam.d/hyprlock" "$policy" hyprlock
not_ok "sudo pam is not installed by default" test -f "$root/etc/pam.d/sudo"
ok "second apply is idempotent" face_auth_apply_policy "$policy" "$mounts"
ok "rollback script restores the original" env FACE_AUTH_ROOT="$root" "$root/usr/local/sbin/delight-face-auth-disable"
is "original hyprlock is back" "$(cat "$root/etc/pam.d/hyprlock")" "ORIGINAL-HYPRLOCK"
not_ok "gate is removed on rollback" test -e "$root/usr/local/lib/omarchy-delight/face-auth-gate"
ok "rollback script remains for a second run" test -x "$root/usr/local/sbin/delight-face-auth-disable"
ok "second rollback is a no-op" env FACE_AUTH_ROOT="$root" "$root/usr/local/sbin/delight-face-auth-disable"
not_ok "rollback script does not shell out to jq" grep -q jq "$root/usr/local/sbin/delight-face-auth-disable"

# A symlink in the model tree blocks apply and does not replace PAM.
ok "apply again before the symlink check" face_auth_apply_policy "$policy" "$mounts"
ln -s /tmp "$root/etc/howdy/models/evil"
not_ok "symlink model is refused" face_auth_apply_policy "$policy" "$mounts"
ok "refused symlink leaves the installed stack in place" grep -q 'face-auth-gate hyprlock' "$root/etc/pam.d/hyprlock"
rm -f -- "$root/etc/howdy/models/evil"

# sudo opt-in creates a file that rollback deletes.
sudo_policy=$(jq -c '.scope.sudo = true' <<<"$policy")
ok "sudo apply" face_auth_apply_policy "$sudo_policy" "$mounts"
ok "sudo pam validates" face_auth_validate_pam_file "$root/etc/pam.d/sudo" "$sudo_policy" sudo
ok "sudo rollback" env FACE_AUTH_ROOT="$root" "$root/usr/local/sbin/delight-face-auth-disable"
is "hyprlock original survived sudo rollback" "$(cat "$root/etc/pam.d/hyprlock")" "ORIGINAL-HYPRLOCK"
not_ok "created sudo pam is deleted" test -e "$root/etc/pam.d/sudo"

# Gate and sleep hook behaviour. Re-apply so the scripts exist.
ok "apply for gate tests" face_auth_apply_policy "$policy" "$mounts"
gate="$root/usr/local/lib/omarchy-delight/face-auth-gate"
sleep_hook="$root/usr/lib/systemd/system-sleep/omarchy-delight-face-auth"
not_ok "no password since boot denies face" env FACE_AUTH_ROOT="$root" "$gate" hyprlock
mkdir -p -- "$root/run/omarchy-delight/face-auth"
printf 'ok\n' >"$root/run/omarchy-delight/face-auth/password-ok"
ok "fresh password stamp allows hyprlock" env FACE_AUTH_ROOT="$root" "$gate" hyprlock
ln -s "$root/run/omarchy-delight/face-auth/password-ok" "$root/run/omarchy-delight/face-auth/password-ok.link"
# The gate checks the real path, not a sibling link. Replace the stamp with a symlink.
rm -f -- "$root/run/omarchy-delight/face-auth/password-ok"
ln -s /tmp/elsewhere "$root/run/omarchy-delight/face-auth/password-ok"
not_ok "symlink password stamp is denied" env FACE_AUTH_ROOT="$root" "$gate" hyprlock
rm -f -- "$root/run/omarchy-delight/face-auth/password-ok"
printf 'ok\n' >"$root/run/omarchy-delight/face-auth/password-ok"
touch -d '2 hours ago' "$root/run/omarchy-delight/face-auth/password-ok"
not_ok "sudo cache expires" env FACE_AUTH_ROOT="$root" "$gate" sudo
touch "$root/run/omarchy-delight/face-auth/password-ok"
ok "fresh stamp allows sudo inside the cache" env FACE_AUTH_ROOT="$root" "$gate" sudo
: >"$root/run/omarchy-delight/face-auth/require-password"
not_ok "suspend flag denies face" env FACE_AUTH_ROOT="$root" "$gate" hyprlock
not_ok "unknown service is denied" env FACE_AUTH_ROOT="$root" "$gate" login
rm -f -- "$root/run/omarchy-delight/face-auth/require-password"
ok "sleep hook exits 0" env FACE_AUTH_ROOT="$root" "$sleep_hook" post suspend
ok "any suspend requires a password when the limit is 0" test -f "$root/run/omarchy-delight/face-auth/require-password"

# A positive limit does not lock out a short suspend, and does lock out a long one.
long=$(face_auth_policy_normalize <<<"$(face_auth_policy_merge "$ROOT/defaults.json" '{"suspend_max_seconds":30}')")
long_stage=$(mktemp -d)
face_auth_render_sleep "$long" >"$long_stage/hook"
chmod 0755 "$long_stage/hook"
rm -f -- "$root/run/omarchy-delight/face-auth/require-password"
printf '%s\n' "$(($(date +%s) - 5))" >"$root/run/omarchy-delight/face-auth/suspend-start"
env FACE_AUTH_ROOT="$root" "$long_stage/hook" post suspend
not_ok "short suspend under the limit does not require a password" test -f "$root/run/omarchy-delight/face-auth/require-password"
printf '%s\n' "$(($(date +%s) - 120))" >"$root/run/omarchy-delight/face-auth/suspend-start"
env FACE_AUTH_ROOT="$root" "$long_stage/hook" post suspend
ok "long suspend requires a password" test -f "$root/run/omarchy-delight/face-auth/require-password"

# Owner check is explicit so a non-root test can still prove uid 0 is required.
ok "matching uid passes the owner rule" face_auth_audit_path "$root/etc/howdy/models/juan.dat" "$EUID"
not_ok "a different uid fails the owner rule" face_auth_audit_path "$root/etc/howdy/models/juan.dat" "$((EUID + 1))"

rm -rf -- "$stage" "$root" "$long_stage"
done_testing
