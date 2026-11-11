#!/usr/bin/env bash

# Apply the Zenbook A16 camera series onto a Linux 7.3 tree and, optionally,
# cross-build the camera objects and the A16 dtb.
#
# This is a bring-up recipe for the vanilla linux-7.3 tarball that
# linux-omarchy-aarch64 7.3-48 starts from. It does not replay Omarchy's
# own patch stack. See README.md before installing the result.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TARBALL_URL="https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3.tar.xz"
TARBALL_SHA256="87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953"
KERNEL_NAME="linux-7.3"

usage() {
  cat <<EOF
Usage:
  build.sh fetch [workdir]
  build.sh apply <kernel-tree>
  build.sh config <kernel-tree>
  build.sh compile <kernel-tree>
  build.sh all [workdir]

fetch downloads linux-7.3.tar.xz, checks its sha256, and extracts it.
apply patches that tree. APPLY_A16_BOARD=0 skips the unverified A16
sensor nodes. APPLY_MCLK4_6MA=1 adds the A16-only MCLK4 6 mA override
(default off; requires the board patch).
config merges config.fragment. It runs arm64 defconfig only when the
tree has no .config yet.
compile builds the camera objects and the A16 dtb. A16_FULL_BUILD=1
builds Image, dtbs and modules instead. That full build was not run
in the cloud VM that checked this recipe.

A16_TARBALL=/path/to/linux-7.3.tar.xz skips the download.
CROSS_COMPILE defaults to aarch64-linux-gnu- when that gcc exists,
and to empty (native) otherwise. Export CROSS_COMPILE= to force native.
EOF
}

cross_make() {
  local tree=$1
  shift
  if [[ ! -v CROSS_COMPILE ]]; then
    if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
      CROSS_COMPILE=aarch64-linux-gnu-
    else
      CROSS_COMPILE=
    fi
  fi
  make -C "$tree" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" "$@"
}

require_tree() {
  local tree=$1
  if [[ ! -f $tree/Makefile || ! -d $tree/arch/arm64 ]]; then
    echo "not a Linux arm64 tree: $tree" >&2
    exit 1
  fi
}

cmd_fetch() {
  local workdir=${1:-/tmp/a16-camera-linux}
  local tarball dest
  mkdir -p "$workdir"
  dest=$workdir/$KERNEL_NAME
  if [[ -d $dest/arch/arm64 ]]; then
    echo "already extracted: $dest"
    return 0
  fi
  if [[ -n ${A16_TARBALL:-} ]]; then
    tarball=$A16_TARBALL
  else
    tarball=$workdir/linux-7.3.tar.xz
    if [[ ! -f $tarball ]]; then
      echo "download $TARBALL_URL"
      curl -fL --retry 3 -o "$tarball.partial" "$TARBALL_URL"
      mv "$tarball.partial" "$tarball"
    fi
  fi
  echo "$TARBALL_SHA256  $tarball" | sha256sum -c -
  tar -C "$workdir" -xf "$tarball"
  echo "extracted $dest"
}

cmd_apply() {
  local tree=$1
  local line patch tag
  require_tree "$tree"
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%#*}
    line=${line#"${line%%[![:space:]]*}"}
    [[ -z $line ]] && continue
    read -r patch tag <<<"$line"
    if [[ ${tag:-} == board && ${APPLY_A16_BOARD:-1} == 0 ]]; then
      echo "skip $patch (APPLY_A16_BOARD=0)"
      continue
    fi
    echo "apply $patch"
    (
      cd -- "$tree"
      git apply --whitespace=nowarn "$ROOT/$patch"
    )
  done <"$ROOT/series"
  if [[ ${APPLY_MCLK4_6MA:-0} == 1 ]]; then
    if [[ ${APPLY_A16_BOARD:-1} == 0 ]]; then
      echo "APPLY_MCLK4_6MA=1 needs the A16 board patch" >&2
      exit 1
    fi
    echo "apply patches/optional/mclk4-drive-6ma.patch"
    (
      cd -- "$tree"
      git apply --whitespace=nowarn "$ROOT/patches/optional/mclk4-drive-6ma.patch"
    )
  fi
}

cmd_config() {
  local tree=$1
  require_tree "$tree"
  if [[ ! -f $tree/.config ]]; then
    cross_make "$tree" defconfig
  fi
  (
    cd -- "$tree"
    scripts/kconfig/merge_config.sh -m .config "$ROOT/config.fragment"
  )
  cross_make "$tree" olddefconfig
}

cmd_compile() {
  local tree=$1
  require_tree "$tree"
  cmd_config "$tree"
  if [[ ${A16_FULL_BUILD:-0} == 1 ]]; then
    echo "full Image/dtbs/modules build (not what the cloud VM ran)"
    cross_make "$tree" -j"$(nproc)" Image dtbs modules
    return 0
  fi
  cross_make "$tree" -j"$(nproc)" \
    drivers/media/i2c/hm1092.o \
    drivers/mfd/qcom-pm8008.o \
    drivers/regulator/qcom-pm8008-regulator.o \
    drivers/phy/qualcomm/phy-qcom-mipi-csi2-core.o \
    drivers/phy/qualcomm/phy-qcom-mipi-csi2-3ph-dphy.o \
    drivers/media/platform/qcom/camss/camss.o \
    qcom/glymur-asus-zenbook-a16-ux3607oa.dtb
}

cmd_all() {
  local workdir=${1:-/tmp/a16-camera-linux}
  cmd_fetch "$workdir"
  cmd_apply "$workdir/$KERNEL_NAME"
  cmd_config "$workdir/$KERNEL_NAME"
  cmd_compile "$workdir/$KERNEL_NAME"
}

main() {
  local cmd=${1:-}
  if [[ -z $cmd ]]; then
    usage >&2
    exit 2
  fi
  shift
  case $cmd in
    fetch) cmd_fetch "$@" ;;
    apply) cmd_apply "$@" ;;
    config) cmd_config "$@" ;;
    compile) cmd_compile "$@" ;;
    all) cmd_all "$@" ;;
    -h | --help | help) usage ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
