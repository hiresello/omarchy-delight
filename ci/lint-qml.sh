#!/bin/bash

# qmllint every staged plugin (each bundles qml/Delight, so the library is linted too).
# Usage: ci/lint-qml.sh <omarchy-checkout>   (resolves the qs.* imports)

set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
DELIGHT_ROOT=$PWD
# shellcheck source=../lib/delight/delight.sh
source lib/delight/delight.sh

OMARCHY=${1:?usage: ci/lint-qml.sh <omarchy-checkout>}
QMLLINT=${QMLLINT:-$(command -v qmllint6 || command -v /usr/lib/qt6/bin/qmllint || command -v qmllint)}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/imports"
ln -s "$(cd -- "$OMARCHY/shell" && pwd)" "$work/imports/qs"

args=(-W 0 -I "$work/imports" -I "$DELIGHT_ROOT/qml")
for plugin in plugins/*/ modules/*/plugin*/; do
  [[ -f $plugin/manifest.json ]] || continue
  name=$(basename -- "$plugin")
  delight_plugin_stage "$plugin" "$work/$name"
done

mapfile -t files < <(find "$work" -path "$work/imports" -prune -o -name '*.qml' -print | sort)
echo "linting ${#files[@]} QML files"
"$QMLLINT" "${args[@]}" "${files[@]}"
