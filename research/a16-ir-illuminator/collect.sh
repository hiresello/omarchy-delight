#!/bin/bash
# Research spike: read-only evidence for the A16 IR illuminator.
# Standalone. Not wired into install. Does not source lib/ or modules/.
# Never writes an LED brightness, an I2C register, or a GPIO.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: collect.sh [--out DIR] [--blobs DIR] [--scan-cci] [--help] [--self-test]

Read-only bundle for the UX3607OA IR illuminator. Default output is
~/a16-ir-evidence. Do not commit that directory.

  --out DIR     where to write the bundle
  --blobs DIR   Windows driver files already copied onto this machine.
                Searches them for flash/LED/strobe strings. Reads only.
  --scan-cci    run i2cdetect on adapters whose name contains "cci".
                Off by default. A scan writes addresses onto the bus.
                Refused while A16_IR_ROOT is set (the self-test fixture).
  --help        this text
  --self-test   fixture run, no hardware, TAP on stdout

Set A16_IR_ROOT to a fake / for tests. Live collection leaves it unset.
EOF
}

die() {
  echo "a16-ir: $*" >&2
  exit 2
}

# Paths are under ${A16_IR_ROOT:-} so the self-test can point at a fixture.
root() {
  printf '%s' "${A16_IR_ROOT:-}"
}

live() {
  [[ -z ${A16_IR_ROOT:-} ]]
}

write_section() {
  local dest=$1
  shift
  {
    if "$@"; then
      :
    else
      echo "exit $?"
    fi
  } >"$dest" 2>&1 || true
}

note_missing() {
  local dest=$1
  shift
  if "$@"; then
    :
  else
    echo "not available" >"$dest"
  fi
}

leds() {
  local base led
  base="$(root)/sys/class/leds"
  if [[ ! -d $base ]]; then
    echo "no $base"
    return 0
  fi
  find "$base" -mindepth 1 -maxdepth 1 \( -type l -o -type d \) -print | sort | while IFS= read -r led; do
    echo "== ${led##*/}"
    for attr in brightness max_brightness trigger color function device/of_node/name; do
      if [[ -r $led/$attr ]]; then
        printf '%s=' "$attr"
        tr '\n' ' ' <"$led/$attr"
        echo
      fi
    done
    echo
  done
}

i2c_adapters() {
  local base n name
  base="$(root)/sys/class/i2c-adapter"
  if [[ ! -d $base ]]; then
    echo "no $base"
    return 0
  fi
  find "$base" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort | while IFS= read -r n; do
    name="$(tr -d '\n' <"$base/$n/name" 2>/dev/null || echo '?')"
    echo "$n name=$name"
  done
}

scan_cci() {
  local base n name num
  live || die "--scan-cci refused while A16_IR_ROOT is set"
  command -v i2cdetect >/dev/null 2>&1 || die "i2cdetect not installed (pacman -S i2c-tools)"
  echo "WARNING: i2cdetect writes a probe to each address. CCI adapters only."
  base="/sys/class/i2c-adapter"
  [[ -d $base ]] || {
    echo "no adapters"
    return 0
  }
  find "$base" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | while IFS= read -r n; do
    name="$(tr -d '\n' <"$base/$n/name" 2>/dev/null || true)"
    if [[ $name != *[Cc][Cc][Ii]* ]]; then
      echo "skip $n ($name)"
      continue
    fi
    echo "==== $n ($name)"
    num=${n#i2c-}
    if command -v timeout >/dev/null 2>&1; then
      timeout 15 i2cdetect -y "$num" || echo "i2cdetect exit $?"
    else
      i2cdetect -y "$num" || echo "i2cdetect exit $?"
    fi
  done
}

regulators() {
  local base r name
  base="$(root)/sys/class/regulator"
  if [[ ! -d $base ]]; then
    echo "no $base"
    return 0
  fi
  find "$base" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort | while IFS= read -r r; do
    name="$(tr -d '\n' <"$base/$r/name" 2>/dev/null || echo '?')"
    echo "$r $name"
  done
}

debugfs_gpio() {
  local f
  f="$(root)/sys/kernel/debug/gpio"
  if [[ -r $f ]]; then
    cat "$f"
  else
    echo "unreadable: $f (root, and debugfs mounted, if this is the live machine)"
  fi
}

gpioinfo_dump() {
  if ! live; then
    echo "skipped on fixture"
    return 0
  fi
  if command -v gpioinfo >/dev/null 2>&1; then
    gpioinfo || echo "gpioinfo exit $?"
  else
    echo "gpioinfo not installed (pacman -S libgpiod)"
  fi
}

devicetree_hits() {
  local base
  base="$(root)/sys/firmware/devicetree/base"
  if [[ ! -d $base ]]; then
    echo "no $base"
    return 0
  fi
  echo "# model"
  if [[ -r $base/model ]]; then
    tr -d '\0' <"$base/model"
    echo
  fi
  echo
  echo "# nodes whose path mentions led, flash, camera, ir, hm1092, pm8010, pmh0101"
  find "$base" -print | tr -d '\0' | grep -Ei 'led|flash|camera|hm1092|ov02c10|pm8010|pmh0101|privacy|ir-' || echo "(no path hits)"
}

running_dtb() {
  local f
  f="$(root)/sys/firmware/fdt"
  if [[ ! -r $f ]]; then
    echo "no $f"
    echo "On a kernel that booted its own DTB this file is that DTB, not a hidden Windows tree."
    return 0
  fi
  if ! live; then
    echo "fixture: $f exists, dtc skipped"
    return 0
  fi
  if command -v dtc >/dev/null 2>&1; then
    dtc -I dtb -O dts -o running.dts "$f" && echo "wrote running.dts beside this log (see the bundle directory)"
    # dtc -o is relative to cwd. Caller cds into the bundle first.
  else
    echo "dtc not installed (pacman -S dtc). Copied raw fdt instead."
    cp -f "$f" running.dtb
  fi
}

acpi_tables() {
  local base name
  base="$(root)/sys/firmware/acpi/tables"
  if [[ ! -d $base ]]; then
    echo "no $base"
    echo "A DT-booted kernel often still exposes firmware ACPI here. Absence means this boot did not."
    return 0
  fi
  find "$base" -maxdepth 2 -type f -printf '%p\n' | sort
  mkdir -p acpi
  find "$base" -maxdepth 2 -type f | while IFS= read -r name; do
    cp -f "$name" "acpi/${name##*/}" 2>/dev/null || echo "unreadable $name"
  done
  if live && command -v iasl >/dev/null 2>&1 && [[ -f acpi/DSDT ]]; then
    iasl -d acpi/DSDT >/dev/null && echo "decompiled acpi/DSDT.dsl"
  else
    echo "iasl not run (install acpica and re-run, or: iasl -d acpi/DSDT)"
  fi
}

kernel_log() {
  if ! live; then
    echo "skipped on fixture"
    return 0
  fi
  if command -v journalctl >/dev/null 2>&1; then
    journalctl -k -b --no-pager | grep -Ei 'camss|cci|hm1092|ov02c10|pm8010|pmh0101|flash|privacy|himax|camcc' || echo "(no matching kernel lines)"
  elif [[ -r /var/log/dmesg ]]; then
    grep -Ei 'camss|cci|hm1092|ov02c10|pm8010|pmh0101|flash|privacy|himax|camcc' /var/log/dmesg || echo "(no matching lines)"
  else
    echo "no journalctl and no /var/log/dmesg"
  fi
}

media_graph() {
  if ! live; then
    echo "skipped on fixture"
    return 0
  fi
  if command -v media-ctl >/dev/null 2>&1; then
    media-ctl -d /dev/media0 -p || echo "media-ctl exit $?"
  else
    echo "media-ctl not installed"
  fi
  echo
  echo "# /dev/video names"
  if compgen -G '/sys/class/video4linux/video*/name' >/dev/null; then
    for f in /sys/class/video4linux/video*/name; do
      printf '%s=' "${f%/name}"
      cat "$f"
    done
  else
    echo "(none)"
  fi
}

usb_cameras() {
  if ! live; then
    echo "skipped on fixture"
    return 0
  fi
  if command -v lsusb >/dev/null 2>&1; then
    lsusb || true
  else
    echo "lsusb not installed"
  fi
  echo
  echo "# uvcvideo bindings (a UVC IR camera would show up here; the A16 sensors should not)"
  if [[ -d /sys/bus/usb/drivers/uvcvideo ]]; then
    ls -1 /sys/bus/usb/drivers/uvcvideo || true
  else
    echo "(no uvcvideo driver directory)"
  fi
}

pinctrl_hits() {
  local base
  base="$(root)/sys/kernel/debug/pinctrl"
  if [[ ! -d $base ]]; then
    echo "no $base"
    return 0
  fi
  find "$base" -name 'pinmux-pins' -print | while IFS= read -r f; do
    echo "==== $f"
    grep -Ei 'cam|led|mclk|cci|flash' "$f" || echo "(no cam/led/mclk/cci/flash lines)"
  done
}

blob_strings() {
  local dir=$1
  [[ -d $dir ]] || {
    echo "no directory: $dir"
    return 0
  }
  echo "# string hits under $dir"
  echo "# tokens: FLASH STROBE ILLUM IR_LED LM364 AW364 PM8550 pmh0101 PM8010 PPP_RESOURCE TLMMGPIO"
  find "$dir" -type f -size -32M -print | sort | while IFS= read -r f; do
    if grep -Iaq -E 'FLASH|STROBE|ILLUM|IR_LED|IRLED|LM364|AW364|PM8550|pmh0101|PM8010|PPP_RESOURCE|TLMMGPIO|flash-led|led-sources' "$f"; then
      echo "==== $f"
      grep -Iao -E '.{0,40}(FLASH|STROBE|ILLUM|IR_LED|IRLED|LM364|AW364|PM8550|pmh0101|PM8010|PPP_RESOURCE|TLMMGPIO|flash-led|led-sources).{0,40}' "$f" | head -n 80 || true
    fi
  done
}

identity() {
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if live; then
    uname -a || true
    echo
    if [[ -r /etc/os-release ]]; then
      cat /etc/os-release
    fi
    echo
    echo "# cmdline"
    tr '\0' ' ' </proc/cmdline || true
    echo
  else
    echo "fixture"
  fi
  echo "# device-tree model"
  local model
  model="$(root)/sys/firmware/devicetree/base/model"
  if [[ -r $model ]]; then
    tr -d '\0' <"$model"
    echo
  else
    echo "(none)"
  fi
}

collect() {
  local out=$1 blobs=$2 do_scan=$3
  mkdir -p "$out"
  cd "$out"
  echo "bundle: $out"

  write_section identity.txt identity
  write_section usb.txt usb_cameras
  write_section leds.txt leds
  write_section i2c-adapters.txt i2c_adapters
  write_section regulators.txt regulators
  write_section debugfs-gpio.txt debugfs_gpio
  write_section gpioinfo.txt gpioinfo_dump
  write_section pinctrl-hits.txt pinctrl_hits
  write_section devicetree-hits.txt devicetree_hits
  write_section running-dtb.txt running_dtb
  write_section acpi.txt acpi_tables
  write_section kernel-log.txt kernel_log
  write_section media.txt media_graph
  if [[ -n $blobs ]]; then
    write_section blob-strings.txt blob_strings "$blobs"
  else
    echo "not requested (pass --blobs DIR)" >blob-strings.txt
  fi
  if [[ $do_scan == yes ]]; then
    write_section i2c-scan-cci.txt scan_cci
  else
    echo "not requested. Re-run with --scan-cci to probe CCI adapters only." >i2c-scan-cci.txt
  fi

  cat >README.txt <<'EOF'
Read-only A16 IR-illuminator evidence. This script did not set an LED,
write an I2C register, or drive a GPIO.

Look at, in this order:
  leds.txt            white privacy indicator versus any flash/IR LED class device
  devicetree-hits.txt and running.dts
                      the booted DTB. A mainline A16 DTB has no IR flash node.
  blob-strings.txt    only if --blobs was given
  i2c-adapters.txt    CCI adapter names. i2c-scan-cci.txt only if --scan-cci
  acpi/               firmware tables, when the kernel exported them
  kernel-log.txt media.txt usb.txt

Do not commit this directory. See docs/a16-ir-illuminator.md.
EOF
}

self_test() {
  local tmp fx out n=0 fail=0
  tmp=$(mktemp -d)
  fx=$tmp/root
  out=$tmp/out
  mkdir -p "$fx/sys/class/leds/white:privacy" \
    "$fx/sys/class/i2c-adapter/i2c-9" \
    "$fx/sys/class/regulator/regulator.0" \
    "$fx/sys/firmware/devicetree/base/leds/privacy-led" \
    "$fx/sys/firmware/acpi/tables" \
    "$fx/sys/kernel/debug"
  printf '0\n' >"$fx/sys/class/leds/white:privacy/brightness"
  printf '1\n' >"$fx/sys/class/leds/white:privacy/max_brightness"
  printf 'none\n' >"$fx/sys/class/leds/white:privacy/trigger"
  printf 'ASUS Zenbook A16 fixture\0' >"$fx/sys/firmware/devicetree/base/model"
  printf 'QCOM-CCI adapter\n' >"$fx/sys/class/i2c-adapter/i2c-9/name"
  printf 'vreg_l4m\n' >"$fx/sys/class/regulator/regulator.0/name"
  printf 'x' >"$fx/sys/firmware/fdt"
  printf 'DSDT' >"$fx/sys/firmware/acpi/tables/DSDT"

  A16_IR_ROOT=$fx collect "$out" "" no

  n=$((n + 1))
  if grep -q 'white:privacy' "$out/leds.txt"; then
    echo "ok $n leds list the fixture privacy LED"
  else
    echo "not ok $n leds list the fixture privacy LED"
    fail=1
  fi

  n=$((n + 1))
  if grep -q 'QCOM-CCI' "$out/i2c-adapters.txt" && grep -q 'not requested' "$out/i2c-scan-cci.txt"; then
    echo "ok $n CCI adapter listed and not scanned"
  else
    echo "not ok $n CCI adapter listed and not scanned"
    fail=1
  fi

  n=$((n + 1))
  if grep -q 'Zenbook A16 fixture' "$out/identity.txt"; then
    echo "ok $n model recorded"
  else
    echo "not ok $n model recorded"
    fail=1
  fi

  n=$((n + 1))
  if [[ -f $script_path ]] && ! grep -E -q '^[[:space:]]*(i2cset|i2ctransfer|i2cdump|gpioset|gpioget)\b' "$script_path"; then
    echo "ok $n script does not call i2cset, i2cdump, or gpioset"
  else
    echo "not ok $n script does not call i2cset, i2cdump, or gpioset"
    fail=1
  fi

  n=$((n + 1))
  if A16_IR_ROOT=$fx "$script_path" --scan-cci --out "$tmp/nope" >/dev/null 2>&1; then
    echo "not ok $n --scan-cci is refused on a fixture"
    fail=1
  else
    echo "ok $n --scan-cci is refused on a fixture"
  fi

  rm -rf "$tmp"
  if [[ $fail -ne 0 ]]; then
    exit 1
  fi
}

script_path=$(readlink -f -- "${BASH_SOURCE[0]}")
out=${A16_IR_OUT:-"$HOME/a16-ir-evidence"}
blobs=
scan=no

while [[ $# -gt 0 ]]; do
  case $1 in
    --out)
      out=${2:?--out needs a directory}
      shift 2
      ;;
    --blobs)
      blobs=${2:?--blobs needs a directory}
      shift 2
      ;;
    --scan-cci)
      scan=yes
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    --self-test)
      self_test
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

collect "$out" "$blobs" "$scan"
echo "wrote $out"
