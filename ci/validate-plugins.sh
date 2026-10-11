#!/bin/bash

# Run Omarchy's own plugin validator over every staged Delight plugin.
# Usage: ci/validate-plugins.sh <omarchy-checkout>

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
DELIGHT_ROOT=$PWD
# shellcheck source=../lib/delight/delight.sh
source lib/delight/delight.sh

OMARCHY=${1:?usage: ci/validate-plugins.sh <omarchy-checkout>}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

count=0
for manifest in plugins/*/manifest.json modules/*/*/manifest.json; do
  [[ -f $manifest ]] || continue
  src=$(dirname -- "$manifest")
  id=$(jq -r .id "$manifest")
  [[ $id == delight.* ]] || {
    echo "FAIL $src: plugin id '$id' must start with delight." >&2
    exit 1
  }
  delight_plugin_stage "$src" "$work/$id"
  bash "$OMARCHY/bin/omarchy-plugin-validate" "$work/$id"
  count=$((count + 1))
done
echo "validated $count plugin(s)"
