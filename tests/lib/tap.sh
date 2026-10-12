#!/bin/bash

# Tiny TAP helpers plus a sandboxed $HOME. Source from a test file:
#   source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/tap.sh"

set -uo pipefail

DELIGHT_TEST_REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
TAP_COUNT=0
TAP_FAILED=0

ok() {
  local desc="$1"
  shift
  TAP_COUNT=$((TAP_COUNT + 1))
  if "$@" >/dev/null 2>&1; then
    echo "ok $TAP_COUNT - $desc"
  else
    echo "not ok $TAP_COUNT - $desc"
    TAP_FAILED=$((TAP_FAILED + 1))
  fi
}

not_ok() {
  local desc="$1"
  shift
  ok "$desc" tap_not "$@"
}

tap_not() {
  ! "$@"
}

is() {
  local desc="$1" got="$2" want="$3"
  TAP_COUNT=$((TAP_COUNT + 1))
  if [[ $got == "$want" ]]; then
    echo "ok $TAP_COUNT - $desc"
  else
    echo "not ok $TAP_COUNT - $desc"
    printf '#   got:  %s\n#   want: %s\n' "${got//$'\n'/$'\n#         '}" "${want//$'\n'/$'\n#         '}"
    TAP_FAILED=$((TAP_FAILED + 1))
  fi
}

done_testing() {
  echo "1..$TAP_COUNT"
  ((TAP_FAILED == 0))
}

# Fresh HOME and XDG_RUNTIME_DIR, with tests/stubs first on PATH. Stubbed
# commands append their argv to $DELIGHT_STUB_LOG.
sandbox() {
  SANDBOX=$(mktemp -d)
  export HOME="$SANDBOX/home"
  export XDG_RUNTIME_DIR="$SANDBOX/run"
  export DELIGHT_STUB_LOG="$SANDBOX/stub.log"
  export DELIGHT_STUB_STATE="$SANDBOX/stub-state"
  export PATH="$DELIGHT_TEST_REPO/tests/stubs:$HOME/.local/bin:$PATH"
  mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$DELIGHT_STUB_STATE"
  : >"$DELIGHT_STUB_LOG"
  unset DELIGHT_LIB_LOADED DELIGHT_DRY_RUN HYPRLAND_INSTANCE_SIGNATURE
  trap 'rm -rf "$SANDBOX"' EXIT
}

# Copy the repo (without .git) so tests can add modules freely.
repo_copy() {
  local dest="$SANDBOX/repo"
  mkdir -p "$dest"
  tar -C "$DELIGHT_TEST_REPO" --exclude=.git --exclude=./daemon/target -cf - . | tar -C "$dest" -xf -
  printf '%s\n' "$dest"
}

# Content hash of every file and link under the given paths.
tree_hash() {
  local path
  for path in "$@"; do
    [[ -e $path || -L $path ]] || continue
    find "$path" \( -type f -o -type l \) -print0 | sort -z | while IFS= read -r -d '' f; do
      if [[ -L $f ]]; then
        printf 'L %s %s\n' "$f" "$(readlink -- "$f")"
      else
        printf 'F %s %s %s\n' "$f" "$(stat -c '%a' -- "$f")" "$(sha256sum <"$f" | cut -d' ' -f1)"
      fi
    done
  done | sha256sum | cut -d' ' -f1
}

# JSON Schema validation (Python is allowed in CI and tests only).
schema_valid() {
  python3 "$DELIGHT_TEST_REPO/ci/validate-json.py" --schema "$1" "$2"
}
