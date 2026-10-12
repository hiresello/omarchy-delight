#!/bin/bash

# Host side of the Delight VM harness, sourced by every vm/* command.
# One machine per $DELIGHT_VM_HOME: a copy-on-write overlay on the sealed
# Omarchy image, its SSH key, and its internal (RAM + disk) snapshots.

set -euo pipefail

VM_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
VM_REPO=$(cd -- "$VM_DIR/.." && pwd)
# shellcheck source=vm/image.env
source "$VM_DIR/image.env"

# Used by the vm/* commands that source this file.
# shellcheck disable=SC2034
{
  VM_HOME=${DELIGHT_VM_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-delight/vm}
  VM_MACHINE=$VM_HOME/machine
  VM_USER=omarchy
  VM_PASSWORD=omarchy
  VM_GUEST_DIR=/tmp/delight-vm
  VM_FRESH=fresh
}

vm_log() { printf 'vm: %s\n' "$*" >&2; }
vm_die() {
  vm_log "$1"
  exit "${2:-1}"
}

vm_need() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null || vm_die "$cmd is missing on the host (see docs/vm.md)"
  done
}

vm_kvm_ok() { [[ -r /dev/kvm && -w /dev/kvm ]]; }

vm_secs() { date +%s; }

# ------------------------------------------------------------------ image

# Sets VM_IMAGE_DIR to a directory holding base.qcow2, vmlinuz, initrd and
# cmdline (the layout of omarchy-iso's vm-seal), downloading and verifying the
# image on first use. DELIGHT_VM_IMAGE: "pinned" (vm/image.env, default),
# "latest" (the channel's latest.json), or a local sealed directory.
vm_image_resolve() {
  local sel=${DELIGHT_VM_IMAGE:-pinned} json f
  case $sel in
    pinned) ;;
    latest)
      json=$(curl -fsSL "https://nightly.omarchy.org/$VM_IMAGE_CHANNEL/latest.json") \
        || vm_die "could not fetch the $VM_IMAGE_CHANNEL latest.json"
      VM_IMAGE_VERSION=$(jq -r .version <<<"$json")
      VM_IMAGE_URL=$(jq -r .vm.url <<<"$json")
      VM_IMAGE_SHA256=$(jq -r .vm.sha256 <<<"$json")
      VM_IMAGE_UNPACKED=$(jq -r .vm.unpacked <<<"$json")
      # Read indirectly in vm_image_fetch; the server's SHA256SUMS decides.
      # shellcheck disable=SC2034
      VM_IMAGE_VMLINUZ_SHA256='' VM_IMAGE_INITRD_SHA256='' VM_IMAGE_CMDLINE_SHA256=''
      ;;
    *)
      [[ -d $sel ]] || vm_die "DELIGHT_VM_IMAGE=$sel is not pinned, latest or a directory"
      VM_IMAGE_DIR=$(realpath "$sel")
      for f in base.qcow2 vmlinuz initrd cmdline; do
        [[ -s $VM_IMAGE_DIR/$f ]] || vm_die "$VM_IMAGE_DIR/$f is missing"
      done
      VM_IMAGE_VERSION=local
      return 0
      ;;
  esac
  VM_IMAGE_DIR=$VM_HOME/images/$VM_IMAGE_VERSION
  [[ -f $VM_IMAGE_DIR/.verified ]] || vm_image_fetch
}

vm_sha_check() { # <file> <expected sha256>
  local got
  got=$(sha256sum <"$1" | cut -d' ' -f1)
  [[ $got == "$2" ]] || vm_die "checksum mismatch for $1: got $got, want $2"
}

vm_image_fetch() {
  local dir=$VM_IMAGE_DIR f want pinned
  mkdir -p "$dir"
  if [[ ! -f $dir/base.qcow2 ]]; then
    vm_log "downloading Omarchy $VM_IMAGE_VERSION VM image (about 4.5 GB) to $dir"
    # A finished .part answers the resume with 416; the checksum decides.
    curl -fL --retry 3 -C - -o "$dir/base.qcow2.part" "$VM_IMAGE_URL" \
      || [[ -s $dir/base.qcow2.part ]] || vm_die "download failed: $VM_IMAGE_URL"
    mv "$dir/base.qcow2.part" "$dir/base.qcow2"
  fi
  vm_log "verifying sha256"
  if ! (vm_sha_check "$dir/base.qcow2" "$VM_IMAGE_SHA256"); then
    rm -f "$dir/base.qcow2"
    vm_die "the image did not match vm/image.env; deleted it, run vm/up again"
  fi

  curl -fsSL -o "$dir/SHA256SUMS" "${VM_IMAGE_UNPACKED%/}/SHA256SUMS" || vm_die "could not fetch SHA256SUMS"
  for f in vmlinuz initrd cmdline; do
    curl -fsSL --retry 3 -o "$dir/$f" "${VM_IMAGE_UNPACKED%/}/$f" || vm_die "could not fetch $f"
    want=$(awk -v f="$f" '$2 == f { print $1 }' "$dir/SHA256SUMS")
    pinned="VM_IMAGE_${f^^}_SHA256"
    [[ -z ${!pinned} || ${!pinned} == "$want" ]] || vm_die "SHA256SUMS disagrees with vm/image.env for $f"
    [[ -n $want ]] || vm_die "SHA256SUMS has no entry for $f"
    vm_sha_check "$dir/$f" "$want"
  done
  printf '%s %s\n' "$VM_IMAGE_VERSION" "$VM_IMAGE_SHA256" >"$dir/.verified"
}

# ---------------------------------------------------------------- machine

vm_pid() { cat "$VM_MACHINE/qemu.pid" 2>/dev/null; }

vm_running() {
  local pid
  pid=$(vm_pid) || return 1
  [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null
}

vm_require_running() {
  vm_running || vm_die "the VM is not running; start it with vm/up"
}

vm_port_free() { ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

vm_free_port() {
  local port
  while :; do
    port=$((20000 + RANDOM % 20000))
    if vm_port_free "$port"; then
      echo "$port"
      return 0
    fi
  done
}

vm_create() {
  vm_log "creating a machine from Omarchy $VM_IMAGE_VERSION"
  rm -rf "$VM_MACHINE"
  mkdir -p "$VM_MACHINE"
  ssh-keygen -q -t ed25519 -N '' -C delight-vm -f "$VM_MACHINE/id_ed25519"
  cat /proc/sys/kernel/random/uuid >"$VM_MACHINE/uuid"
  qemu-img create -q -f qcow2 -b "$VM_IMAGE_DIR/base.qcow2" -F qcow2 "$VM_MACHINE/disk.qcow2"
  printf '%s\n' "$VM_IMAGE_DIR" >"$VM_MACHINE/image"
}

vm_machine_image() { cat "$VM_MACHINE/image" 2>/dev/null; }

# Boots the machine, optionally straight into an internal snapshot.
vm_start() { # [snapshot]
  local loadvm=${1:-} image keys ssh_port qmp_port res
  image=$(vm_machine_image)
  ssh_port=${DELIGHT_VM_SSH_PORT:-$(vm_free_port)}
  qmp_port=$(vm_free_port)
  [[ $qmp_port != "$ssh_port" ]] || qmp_port=$((ssh_port + 1))
  res=${DELIGHT_VM_RESOLUTION:-1920x1080}
  echo "$ssh_port" >"$VM_MACHINE/ssh_port"
  echo "$qmp_port" >"$VM_MACHINE/qmp_port"
  # The key reaches the guest as a systemd credential, as omarchy-iso's vm-boot does.
  keys=$(printf 'd /home/%s/.ssh 0700 %s %s -\nf+ /home/%s/.ssh/authorized_keys 0600 %s %s - %s\n' \
    "$VM_USER" "$VM_USER" "$VM_USER" "$VM_USER" "$VM_USER" "$VM_USER" \
    "$(cat "$VM_MACHINE/id_ed25519.pub")" | base64 -w0)
  # shellcheck disable=SC2054 # commas belong to QEMU's option syntax
  local args=(
    -name delight-vm -cpu host -enable-kvm -machine q35,accel=kvm
    -smp "${DELIGHT_VM_SMP:-4}" -m "${DELIGHT_VM_MEM:-4G}"
    -kernel "$image/vmlinuz" -initrd "$image/initrd" -append "$(cat "$image/cmdline")"
    -uuid "$(cat "$VM_MACHINE/uuid")"
    -drive "file=$VM_MACHINE/disk.qcow2,format=qcow2,if=none,id=d0,discard=unmap" -device virtio-blk-pci,drive=d0
    -smbios "type=11,value=io.systemd.credential.binary:tmpfiles.extra=$keys"
    -device "virtio-vga,xres=${res%x*},yres=${res#*x}" -device virtio-rng-pci -display none
    -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$ssh_port-:22" -device virtio-net-pci,netdev=n0
    -qmp "tcp:127.0.0.1:$qmp_port,server=on,wait=off"
    -serial "file:$VM_MACHINE/serial.log"
    -pidfile "$VM_MACHINE/qemu.pid" -daemonize
  )
  [[ -z $loadvm ]] || args+=(-loadvm "$loadvm")
  rm -f "$VM_MACHINE/qemu.pid"
  qemu-system-x86_64 "${args[@]}" || vm_die "qemu failed to start"
}

vm_ssh_opts() {
  printf '%s\n' -i "$VM_MACHINE/id_ed25519" -p "$(cat "$VM_MACHINE/ssh_port")" \
    -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ServerAliveInterval=15
}

vm_ssh() { # [ssh options...]
  local opts
  mapfile -t opts < <(vm_ssh_opts)
  # shellcheck disable=SC2029 # ssh options, not a remote command
  ssh "${opts[@]}" "$@" "$VM_USER@127.0.0.1"
}

# Runs one command line (already quoted for the guest shell) over SSH.
vm_sh() {
  local opts
  mapfile -t opts < <(vm_ssh_opts)
  # shellcheck disable=SC2029 # expanding on the host is the point
  ssh "${opts[@]}" "$VM_USER@127.0.0.1" "$1"
}

vm_wait_ssh() { # [timeout seconds]
  local deadline=$(($(vm_secs) + ${1:-300})) opts
  mapfile -t opts < <(vm_ssh_opts)
  until ssh "${opts[@]}" -o ConnectTimeout=2 "$VM_USER@127.0.0.1" true </dev/null 2>/dev/null; do
    vm_running || vm_die "qemu exited before SSH came up (see $VM_MACHINE/serial.log)"
    (($(vm_secs) < deadline)) || vm_die "no SSH after ${1:-300}s"
    sleep 0.5
  done
}

vm_stop() {
  local pid i
  vm_running || return 0
  pid=$(vm_pid)
  vm_sh 'sudo -n systemctl poweroff' </dev/null >/dev/null 2>&1 || vm_qmp '{"execute":"system_powerdown"}' >/dev/null 2>&1 || true
  for ((i = 0; i < 60; i++)); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.5
  done
  if kill -0 "$pid" 2>/dev/null; then
    vm_qmp '{"execute":"quit"}' >/dev/null 2>&1 || kill "$pid" 2>/dev/null || true
    sleep 1
  fi
  kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
  rm -f "$VM_MACHINE/qemu.pid"
}

# ------------------------------------------------------------------- QMP

# Sends one QMP command over the machine's TCP monitor and prints its reply.
vm_qmp() { # <json>
  local fd line
  exec {fd}<>"/dev/tcp/127.0.0.1/$(cat "$VM_MACHINE/qmp_port")" || return 1
  IFS= read -r -t 10 line <&"$fd" || return 1
  printf '%s\n' '{"execute":"qmp_capabilities"}' >&"$fd"
  vm_qmp_reply "$fd" >/dev/null || return 1
  printf '%s\n' "$1" >&"$fd"
  vm_qmp_reply "$fd"
  local rc=$?
  exec {fd}>&-
  return "$rc"
}

vm_qmp_reply() { # <fd>: skip events, print the return or error
  local line
  while IFS= read -r -t "${VM_QMP_TIMEOUT:-600}" line <&"$1"; do
    if [[ $line == *'"return"'* || $line == *'"error"'* ]]; then
      printf '%s\n' "$line"
      [[ $line == *'"return"'* ]]
      return
    fi
  done
  return 1
}

vm_hmp() { # <monitor command>: prints its output; fails on an Error line
  local reply out
  reply=$(vm_qmp "$(jq -nc --arg c "$1" '{execute: "human-monitor-command", arguments: {"command-line": $c}}')") \
    || vm_die "QMP: $1 failed: $reply"
  out=$(jq -r '.return' <<<"$reply")
  if [[ $out == *Error* || $out == *error:* ]]; then
    vm_log "$1: ${out//$'\r'/}"
    return 1
  fi
  printf '%s' "${out//$'\r'/}"
}

# -------------------------------------------------------------- snapshots

vm_snapshots() {
  [[ -f $VM_MACHINE/disk.qcow2 ]] || return 0
  qemu-img snapshot -U -l "$VM_MACHINE/disk.qcow2" 2>/dev/null | awk 'NR > 2 { print $2 }'
}

vm_has_snapshot() { vm_snapshots | grep -qxF -- "$1"; }

vm_snapshot_save() {
  local t0
  t0=$(vm_secs)
  vm_hmp "savevm $1" >/dev/null || vm_die "could not save snapshot $1"
  vm_log "saved snapshot $1 in $(($(vm_secs) - t0))s"
}

vm_snapshot_delete() { vm_hmp "delvm $1" >/dev/null; }

vm_snapshot_load() {
  vm_hmp "loadvm $1" >/dev/null || vm_die "could not restore snapshot $1"
  vm_after_restore
}

# A restored guest wakes with the clock of the moment it was saved.
vm_after_restore() {
  vm_wait_ssh 120
  vm_sh "sudo -n date -u -s @$(date -u +%s) >/dev/null" </dev/null || vm_log "could not set the guest clock"
}

# ------------------------------------------------------------- guest side

# Copies vm/lib/guest.sh to the guest; the commands below source it there.
vm_push_lib() {
  vm_sh "mkdir -p $VM_GUEST_DIR && cat >$VM_GUEST_DIR/lib.sh" <"$VM_DIR/lib/guest.sh"
}

# Runs a guest command line as the desktop user with the session environment.
vm_guest() { # <command line>
  vm_sh "source $VM_GUEST_DIR/lib.sh && vm_session_env && $1"
}

# Output directory of this invocation: vm/out/<timestamp>/{tap,logs,screenshots}.
vm_out_init() {
  VM_OUT=${DELIGHT_VM_OUT:-$VM_DIR/out/$(date -u +%Y%m%dT%H%M%SZ)}
  mkdir -p "$VM_OUT/tap" "$VM_OUT/logs" "$VM_OUT/screenshots"
  if [[ -z ${DELIGHT_VM_OUT:-} ]]; then
    ln -sfn "$(basename "$VM_OUT")" "$VM_DIR/out/latest"
  fi
  export DELIGHT_VM_OUT=$VM_OUT
}

vm_slug() { # <path>: repo-relative name usable as a file name
  local rel
  rel=$(realpath -m --relative-to="$VM_REPO" "$1")
  [[ $rel != ../* ]] || rel=$(basename "$1")
  rel=${rel%.sh}
  printf '%s\n' "${rel//\//_}"
}

# Runs a host script in the guest; stdout and stderr pass through, artifacts
# the script leaves (vm_screenshot, vm_artifact) land in $VM_OUT.
vm_run_script() { # <script> [args...]
  local script=$1 slug remote cmd
  shift
  [[ -f $script ]] || vm_die "no such script: $script"
  slug=$(vm_slug "$script")
  remote=$VM_GUEST_DIR/run/$slug.sh
  vm_sh "mkdir -p $VM_GUEST_DIR/run && rm -rf $VM_GUEST_DIR/artifacts && cat >$remote" <"$script"
  printf -v cmd '%q ' "$@"
  set +e
  vm_guest "export DELIGHT_VM_TEST=$slug && cd \"\$DELIGHT_ROOT\" 2>/dev/null || cd; timeout -k 10 ${DELIGHT_VM_TEST_TIMEOUT:-900} bash $remote $cmd" </dev/null
  local rc=$?
  set -e
  vm_collect_artifacts
  return "$rc"
}

vm_collect_artifacts() {
  vm_sh "[ -d $VM_GUEST_DIR/artifacts ] && tar -C $VM_GUEST_DIR/artifacts -cf - . || true" </dev/null \
    | tar -C "$VM_OUT" -xf - 2>/dev/null || true
}

# PNG from grim in the guest; falls back to QEMU's own screendump (PPM).
vm_screenshot_to() { # <file.png> [settle seconds]
  local dest=$1
  sleep "${2:-${DELIGHT_VM_SETTLE:-3}}"
  if vm_guest 'grim -' </dev/null >"$dest.tmp" 2>/dev/null && [[ $(head -c 4 "$dest.tmp" | od -An -tx1 | tr -d ' ') == 89504e47 ]]; then
    mv "$dest.tmp" "$dest"
    return 0
  fi
  rm -f "$dest.tmp"
  vm_log "grim failed; using QEMU screendump"
  vm_qmp "$(jq -nc --arg f "${dest%.png}.ppm" '{execute: "screendump", arguments: {filename: $f}}')" >/dev/null
}
