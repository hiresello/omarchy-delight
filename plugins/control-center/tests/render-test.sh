#!/bin/bash

# Offscreen render test: drives the real Control Center QML in Quickshell
# against 8 fixture status files (every state) and a stubbed `delight`.
# Needs quickshell + an Omarchy checkout (OMARCHY_DIR, /usr/share/omarchy or
# /tmp/omarchy); skips otherwise. Screenshots land in DELIGHT_TEST_OUT.

set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "$here/../../.." && pwd)

omarchy=""
for dir in "${OMARCHY_DIR:-}" /usr/share/omarchy /tmp/omarchy; do
  if [[ -n $dir && -f $dir/shell/Commons/Color.qml ]]; then
    omarchy=$dir
    break
  fi
done
if ! command -v quickshell >/dev/null 2>&1 || [[ -z $omarchy ]]; then
  echo "1..0 # SKIP needs quickshell and an Omarchy checkout"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
out=${DELIGHT_TEST_OUT:-$work/out}
mkdir -p "$out" "$out/empty-status" "$work/run/omarchy-delight/status" "$work/bin"

# Stage like delight_plugin_stage: plugin copy + bundled Delight, then the
# Omarchy shell's qs.* modules next to the harness entry point.
cp -r "$root/plugins/control-center" "$work/cc"
rm -rf "$work/cc/Delight"
cp -r "$root/qml/Delight" "$work/cc/Delight"
# Quickshell only resolves imports inside the config folder, so the harness
# runs from the staged plugin root with its relative imports rewritten.
cp -r "$omarchy/shell/Commons" "$omarchy/shell/Ui" "$work/cc/"
for qml in "$here"/harness/*.qml; do
  sed -e '/^import "\.\.\/\.\."$/d' -e 's#^import "\.\./\.\./Delight"$#import "Delight"#' "$qml" >"$work/cc/$(basename -- "$qml")"
done
cp "$here"/fixtures/status/*.json "$work/run/omarchy-delight/status/"
cp "$here/fixtures/stub-delight" "$work/bin/delight"
cp "$here/fixtures/devices.json" "$here/fixtures/list.tsv" "$work/bin/"
: >"$work/delight.log"

ids=""
for f in "$here"/fixtures/status/*.json; do
  ids+="$(basename -- "$f" .json) "
done

wallpapers=()
for theme in ${DELIGHT_TEST_THEMES:-tokyo-night catppuccin-latte}; do
  bg=$(find "$omarchy/themes/$theme/backgrounds" -maxdepth 1 -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.webp' \) 2>/dev/null | sort | head -n1)
  wallpapers+=("DELIGHT_TEST_WALLPAPER_${theme//-/_}=${bg:-}")
done

status=0
env "${wallpapers[@]}" \
  PATH="$work/bin:$PATH" \
  XDG_RUNTIME_DIR="$work/run" \
  QT_QPA_PLATFORM=offscreen \
  QT_QUICK_BACKEND=software \
  DELIGHT_STUB_LOG="$work/delight.log" \
  DELIGHT_TEST_OUT="$out" \
  DELIGHT_TEST_OMARCHY="$omarchy" \
  DELIGHT_TEST_IDS="$ids" \
  timeout 90 quickshell --no-duplicate -p "$work/cc/shell.qml" >"$work/quickshell.log" 2>&1 || status=$?

if [[ ! -s $out/results.tap ]]; then
  echo "1..1"
  echo "not ok 1 - harness produced no results (quickshell exit $status)"
  sed 's/^/# /' "$work/quickshell.log" | tail -n 40
  exit 1
fi
cat "$out/results.tap"
if grep -q '^not ok' "$out/results.tap"; then
  sed 's/^/# /' "$work/quickshell.log" | grep -iE 'warn|error' | tail -n 20 || true
  sed 's/^/# delight /' "$work/delight.log"
  exit 1
fi
