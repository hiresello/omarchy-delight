#!/bin/bash

# Branches named track/<id> may only change paths owned by <id> in
# ci/ownership.json, unless the PR carries the "contract-change" label.
#
# Usage: ci/check-ownership.sh <branch> <labels-json> < changed-files
#   e.g. git diff --name-only origin/main...HEAD | ci/check-ownership.sh "$BRANCH" '["bug"]'

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

branch="${1:-}"
labels="${2:-[]}"

if [[ $branch != track/* ]]; then
  echo "ownership: '$branch' is not a track branch; nothing to check"
  exit 0
fi
track=${branch#track/}

if ! jq -e --arg t "$track" 'has($t)' ci/ownership.json >/dev/null; then
  echo "ownership: unknown track '$track' (see ci/ownership.json)" >&2
  exit 1
fi
if jq -e 'index("contract-change")' <<<"$labels" >/dev/null; then
  echo "ownership: contract-change label present; skipping"
  exit 0
fi

mapfile -t globs < <(jq -r --arg t "$track" '.[$t][]' ci/ownership.json)

owned() {
  local file="$1" glob
  for glob in "${globs[@]}"; do
    # shellcheck disable=SC2053
    [[ $file == ${glob//\*\*/*} ]] && return 0
  done
  return 1
}

bad=()
while IFS= read -r file; do
  [[ -n $file ]] || continue
  owned "$file" || bad+=("$file")
done

if ((${#bad[@]} > 0)); then
  echo "ownership: track/$track may only change: ${globs[*]}" >&2
  printf '  not owned: %s\n' "${bad[@]}" >&2
  echo "Add the 'contract-change' label if this is an intentional contract change." >&2
  exit 1
fi
echo "ownership: ok (track/$track)"
