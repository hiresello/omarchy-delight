#!/bin/bash

# Guest side of the Delight VM harness. vm/run copies this into the VM and
# sources it before running a script; vm-*.sh tests source it again through
# $DELIGHT_VM_LIB for the helpers below.

export DELIGHT_VM=1
export DELIGHT_VM_LIB=${DELIGHT_VM_LIB:-/tmp/delight-vm/lib.sh}
export DELIGHT_VM_ARTIFACTS=${DELIGHT_VM_ARTIFACTS:-/tmp/delight-vm/artifacts}
export DELIGHT_VM_STATE=${DELIGHT_VM_STATE:-$HOME/.local/state/delight-vm}
export DELIGHT_VM_PRISTINE=$DELIGHT_VM_STATE/pristine
export DELIGHT_VM_TEST=${DELIGHT_VM_TEST:-adhoc}

# The installed checkout (install.sh symlinks ~/.local/share/omarchy-delight to
# it; uninstall.sh removes the link, so resolve it while it exists).
if [[ -z ${DELIGHT_ROOT:-} ]]; then
  if [[ -L $HOME/.local/share/omarchy-delight ]]; then
    DELIGHT_ROOT=$(readlink -f "$HOME/.local/share/omarchy-delight")
  else
    DELIGHT_ROOT=$HOME/.local/src/omarchy-delight
  fi
fi
export DELIGHT_ROOT

# Imports the desktop session's environment (WAYLAND_DISPLAY,
# HYPRLAND_INSTANCE_SIGNATURE, DBUS_SESSION_BUS_ADDRESS, OMARCHY_PATH, PATH)
# from the systemd user manager, waiting up to a minute for Hyprland.
vm_session_env() {
  local line i
  for ((i = 0; i < 60; i++)); do
    if pgrep -u "$(id -u)" -x Hyprland >/dev/null \
      && systemctl --user show-environment 2>/dev/null | grep -q '^WAYLAND_DISPLAY='; then
      break
    fi
    sleep 1
  done
  while IFS= read -r line; do
    if [[ $line =~ ^[A-Za-z_][A-Za-z0-9_]*= && $line != *"=\$'"* ]]; then
      export "${line?}"
    fi
  done < <(systemctl --user show-environment 2>/dev/null)
  export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH=$HOME/.local/bin:$PATH ;;
  esac
  export PATH
}

# sudo without a prompt: the harness grants the test user NOPASSWD sudo when it
# prepares the fresh snapshot; the image's password is the fallback, which
# takes stdin, so the command cannot read it.
vm_sudo() {
  if sudo -n true 2>/dev/null; then
    sudo -n "$@"
  else
    printf '%s\n' "${DELIGHT_VM_PASSWORD:-omarchy}" | sudo -S -p '' "$@"
  fi
}

# Saves a screenshot of the whole desktop as screenshots/<test>/<name>.png in
# the host's run directory, after giving the shell time to settle (plugin
# changes reload Quickshell, which blanks the wallpaper for a moment).
vm_screenshot() { # <name> [settle seconds]
  local dir=$DELIGHT_VM_ARTIFACTS/screenshots/$DELIGHT_VM_TEST
  mkdir -p "$dir"
  sleep "${2:-${DELIGHT_VM_SETTLE:-3}}"
  grim "$dir/$1.png"
}

# Copies a file into logs/<test>/ in the host's run directory.
vm_artifact() { # <file> [name]
  local dir=$DELIGHT_VM_ARTIFACTS/logs/$DELIGHT_VM_TEST
  mkdir -p "$dir"
  cp -- "$1" "$dir/${2:-$(basename -- "$1")}"
}

# Polls a command until it succeeds or the timeout (seconds) passes.
vm_wait_for() { # <seconds> <command...>
  local deadline=$((SECONDS + $1))
  shift
  until "$@" >/dev/null 2>&1; do
    ((SECONDS < deadline)) || return 1
    sleep 0.5
  done
}
