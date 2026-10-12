#!/bin/bash

# VM acceptance run for the Control Center on a headless sway session:
# 8 fixture status files, bar click -> first panel frame latency (20 runs),
# real keyboard input via wtype, live theme switch, grim screenshots.
# Needs: sway wtype grim quickshell, OMARCHY_DIR (an Omarchy checkout).
# Usage: OMARCHY_DIR=... DELIGHT_TEST_OUT=dir plugins/control-center/acceptance/live.sh

set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
plugin=$(cd -- "$here/.." && pwd)
root=$(cd -- "$plugin/../.." && pwd)
omarchy=${OMARCHY_DIR:-/usr/share/omarchy}

for tool in sway wtype grim quickshell; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "missing $tool" >&2
    exit 2
  fi
done

work=$(mktemp -d)
trap 'kill "${keyboard_pid:-0}" "${sway_pid:-0}" 2>/dev/null || true; rm -rf "$work"' EXIT
out=${DELIGHT_TEST_OUT:-$work/out}
run="$work/run"
mkdir -p "$out" "$run/omarchy-delight/status" "$work/bin"
chmod 700 "$run"

cp -r "$plugin" "$work/cc"
rm -rf "$work/cc/Delight"
cp -r "$root/qml/Delight" "$work/cc/Delight"
cp -r "$omarchy/shell/Commons" "$omarchy/shell/Ui" "$work/cc/"
# Quickshell only resolves imports inside the config folder: run from the
# staged plugin root with the relative imports rewritten.
sed -e '/^import "\.\."$/d' -e 's#^import "\.\./Delight"$#import "Delight"#' "$here/live.qml" >"$work/cc/shell.qml"
cp "$plugin"/tests/fixtures/status/*.json "$run/omarchy-delight/status/"
cp "$plugin/tests/fixtures/stub-delight" "$work/bin/delight"
cp "$plugin/tests/fixtures/devices.json" "$plugin/tests/fixtures/list.tsv" "$work/bin/"
: >"$work/delight.log"

printf 'output HEADLESS-1 resolution 1280x800\ndefault_border none\n' >"$work/sway.conf"
XDG_RUNTIME_DIR=$run WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman \
  sway -c "$work/sway.conf" >"$work/sway.log" 2>&1 &
sway_pid=$!
for _ in $(seq 50); do
  [[ -S $run/wayland-1 ]] && break
  sleep 0.1
done

# A headless seat has no keyboard until one exists; keep a virtual one
# attached for the whole run so layer-shell focus behaves like a desktop.
XDG_RUNTIME_DIR=$run WAYLAND_DISPLAY=wayland-1 wtype -s 150000 -k Shift_L >/dev/null 2>&1 &
keyboard_pid=$!
sleep 0.3

status=0
env PATH="$work/bin:$PATH" XDG_RUNTIME_DIR="$run" WAYLAND_DISPLAY=wayland-1 QT_QPA_PLATFORM=wayland \
  DELIGHT_STUB_LOG="$work/delight.log" DELIGHT_TEST_OUT="$out" DELIGHT_TEST_OMARCHY="$omarchy" \
  timeout 120 quickshell --no-duplicate -p "$work/cc/shell.qml" >"$work/quickshell.log" 2>&1 || status=$?

if [[ ! -s $out/live.tap ]]; then
  echo "not ok - live run produced no results (quickshell exit $status)"
  tail -n 30 "$work/quickshell.log" "$work/sway.log"
  exit 1
fi
cat "$out/live.tap"
grep -E 'helper exit [^0]|helper:' "$work/quickshell.log" | sed 's/^/# /' || true
! grep -q '^not ok' "$out/live.tap"
