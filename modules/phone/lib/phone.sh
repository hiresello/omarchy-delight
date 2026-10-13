#!/bin/bash

# The iPhone link is delightd (daemon/), Delight's own Rust implementation of
# Apple's ANCS and AMS Bluetooth LE services. This file installs it and
# turns its status into Delight's contract.

PHONE_ICON="󰀷"
PHONE_RELEASE_URL="https://github.com/hiresello/omarchy-delight/releases/latest/download"

phone_daemon_bin() {
  printf '%s\n' "$HOME/.local/lib/omarchy-delight/delightd"
}

phone_daemon_status_file() {
  printf '%s\n' "$XDG_RUNTIME_DIR/omarchy-delight/delightd.json"
}

phone_build_dir() {
  printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-delight/delightd-target"
}

phone_daemon_installed() {
  [[ -x ${DELIGHT_DELIGHTD:-$(phone_daemon_bin)} ]]
}

phone_daemon() {
  local bin
  bin=${DELIGHT_DELIGHTD:-$(phone_daemon_bin)}
  [[ -x $bin ]] || return 127
  "$bin" "$@"
}

phone_daemon_status() {
  local file
  file=$(phone_daemon_status_file)
  if [[ -s $file ]] && jq -e 'type == "object"' "$file" >/dev/null 2>&1; then
    cat -- "$file"
  else
    printf '%s\n' '{}'
  fi
}

# Print the path of a delightd binary to install: a prebuilt one, a local
# cargo build, or a release download. Fails when none is available.
phone_daemon_obtain() {
  local root="$DELIGHT_ROOT/daemon" built arch tmp
  if [[ -n ${DELIGHT_DELIGHTD_SOURCE:-} ]]; then
    [[ -x $DELIGHT_DELIGHTD_SOURCE ]] || return 1
    printf '%s\n' "$DELIGHT_DELIGHTD_SOURCE"
    return 0
  fi
  built="$(phone_build_dir)/release/delightd"
  if [[ ! -x $built ]] && delight_has_cmd cargo && [[ -f $root/Cargo.toml ]]; then
    delight_log "phone: building delightd"
    CARGO_TARGET_DIR="$(phone_build_dir)" \
      cargo build --quiet --release --locked --manifest-path "$root/Cargo.toml" >&2 || return 1
  fi
  if [[ -x $built ]]; then
    printf '%s\n' "$built"
    return 0
  fi
  delight_has_cmd curl || return 1
  arch=$(uname -m)
  tmp="$DELIGHT_STATE_DIR/phone/delightd.download"
  mkdir -p -- "${tmp%/*}"
  curl -fsSL --max-time 60 -o "$tmp" "$PHONE_RELEASE_URL/delightd-$arch" || {
    rm -f -- "$tmp"
    return 1
  }
  chmod +x -- "$tmp"
  printf '%s\n' "$tmp"
}

phone_module_install() {
  local src
  delight_module_default_install
  if delight_dry; then
    delight_dry_print "install delightd to $(phone_daemon_bin)"
    return 0
  fi
  if src=$(phone_daemon_obtain); then
    if ! cmp -s -- "$src" "$(phone_daemon_bin)"; then
      delight_file_install phone "$src" "$(phone_daemon_bin)"
      chmod +x -- "$(phone_daemon_bin)"
    fi
  else
    delight_warn "phone: could not build or download delightd; the iPhone link stays off until 'delight phone install' succeeds"
  fi
  rm -f -- "$DELIGHT_STATE_DIR/phone/delightd.download"
}

phone_now_playing() {
  jq -r '
    .nowPlaying // empty |
    select(.title != null) |
    (if .playing then "▶ " else "❚❚ " end) + .title + (if .artist then " · " + .artist else "" end)
  ' <<<"$1"
}

phone_devices_json() {
  jq -c '[(.phones // [])[] | select(.paired) | {
    id: .address, name: .name, kind: "phone", transport: "ble",
    connected: .connected, rssi: null, mac: .address
  }]' <<<"$(phone_daemon_status)"
}

phone_status_json() {
  local title state subtitle reason="" daemon actions phones connected playing
  title=$(delight_module_field phone '.name')
  actions='[{"label":"Open","command":["delight","phone","open"]},{"label":"Pair","command":["delight","phone","pair"]}]'
  daemon=$(phone_daemon_status)
  if ! delight_is_installed phone; then
    state=needs-setup
    subtitle="Not installed"
    actions='[{"label":"Install","command":["delight","phone","install"]}]'
  elif ! delight_hw_bluetooth; then
    state=unsupported
    subtitle="No Bluetooth"
    reason="No Bluetooth adapter found; the iPhone link needs Bluetooth LE"
  elif ! phone_daemon_installed; then
    state=needs-setup
    subtitle="Finish setup"
    reason="The native iPhone link (delightd) isn't installed yet"
    actions='[{"label":"Set up","command":["delight","phone","install"]}]'
  elif ! delight_module_enabled; then
    state=off
    subtitle="Off"
  elif [[ $(jq -r '.error // empty' <<<"$daemon") != "" ]]; then
    state=error
    subtitle="Bluetooth problem"
    reason=$(jq -r '.error' <<<"$daemon")
    actions='[{"label":"Fix","command":["delight","phone","doctor"]}]'
  else
    state=on
    phones=$(jq '[(.phones // [])[] | select(.paired)] | length' <<<"$daemon")
    connected=$(jq -r '[(.phones // [])[] | select(.paired and .connected)][0].name // empty' <<<"$daemon")
    playing=$(phone_now_playing "$daemon")
    if [[ $daemon == "{}" ]]; then
      subtitle="Starting…"
    elif [[ $(jq -r '.pairing // false' <<<"$daemon") == "true" ]]; then
      subtitle="Pairing — tap $(phone_hostname) on your iPhone"
    elif ((phones == 0)); then
      subtitle="No iPhone paired"
    elif [[ -n $playing ]]; then
      subtitle=$playing
      actions=$(jq -cn --argjson a "$actions" '$a + [{label:"Play/Pause",command:["delight","phone","media","toggle"]},{label:"Next",command:["delight","phone","media","next"]}]')
    elif [[ -n $connected ]]; then
      subtitle="$connected · connected"
    else
      subtitle="Not connected"
    fi
  fi
  local args=(--id phone --state "$state" --title "$title" --subtitle "$subtitle" --icon "$PHONE_ICON"
    --toggle true --actions "$actions" --devices "$(phone_devices_json)")
  [[ -z $reason ]] || args+=(--reason "$reason")
  delight_status_json "${args[@]}"
}

phone_hostname() {
  local name
  name=$(cat /etc/hostname 2>/dev/null || true)
  printf '%s\n' "${name:-Omarchy}"
}

# Exit codes: 0 ok, 1 fixable, 2 unsupported, 3 needs user action.
phone_doctor() {
  local rc=0 daemon unit units
  if ! delight_hw_bluetooth; then
    printf '%s\n' "unsupported: no Bluetooth adapter"
    return 2
  fi
  if ! delight_pkg_present bluez; then
    printf '%s\n' "missing package: bluez (run: delight phone install)"
    rc=1
  fi
  if [[ ! -x ${DELIGHT_DELIGHTD:-$(phone_daemon_bin)} ]]; then
    printf '%s\n' "delightd is not installed (run: delight phone install)"
    rc=1
  fi
  if delight_has_cmd systemctl && ! systemctl is-active --quiet bluetooth.service 2>/dev/null; then
    printf '%s\n' "bluetooth.service is not running (run: sudo systemctl enable --now bluetooth)"
    rc=1
  fi
  units=$(delight_module_units)
  while IFS= read -r unit; do
    [[ -n $unit ]] || continue
    # A .path unit's oneshot service is inactive between runs.
    if [[ $unit == *.service ]] && grep -qxF "${unit%.service}.path" <<<"$units"; then
      continue
    fi
    if delight_module_enabled && ! systemctl --user is-active --quiet "$unit"; then
      printf 'inactive unit: %s (run: delight phone enable)\n' "$unit"
      rc=1
    fi
  done <<<"$units"
  daemon=$(phone_daemon_status)
  if [[ $(jq -r '.error // empty' <<<"$daemon") != "" ]]; then
    printf '%s\n' "$(jq -r '.error' <<<"$daemon")"
    rc=1
  fi
  if ((rc == 0)) && [[ $(jq '[(.phones // [])[] | select(.paired)] | length' <<<"$daemon") == "0" ]]; then
    printf '%s\n' "no iPhone paired (run: delight phone pair)"
    return 3
  fi
  ((rc != 0)) || printf '%s\n' "ok"
  return "$rc"
}

module_install() {
  phone_module_install
}

module_uninstall() {
  delight_module_default_uninstall
  delight_rm "$(phone_build_dir)"
  delight_rmdir_empty "$(dirname -- "$(phone_build_dir)")"
}

module_enable() {
  phone_daemon_installed || delight_die "phone: delightd isn't installed (run: delight phone install)"
  delight_module_default_enable
}

module_publish() {
  delight_module_publish
}

module_status() {
  phone_status_json
}

module_doctor() {
  phone_doctor
}

module_devices() {
  [[ ${1:-} == "--json" ]] || delight_die "usage: delight phone devices --json" 64
  phone_devices_json
}

module_pair() {
  delight_module_enabled || delight_module_call enable
  phone_daemon pair >/dev/null || delight_die "phone: delightd is not running (try: delight phone doctor)"
  delight_notify phone "Pair your iPhone" \
    "On the iPhone, open Settings › Bluetooth and tap $(phone_hostname), then allow notifications."
  delight_module_publish
}

module_media() {
  local cmd="${1:-}"
  case "$cmd" in
    play | pause | toggle | next | previous | volume-up | volume-down) ;;
    *) delight_die "usage: delight phone media <play|pause|toggle|next|previous|volume-up|volume-down>" 64 ;;
  esac
  phone_daemon media "$cmd" >/dev/null || delight_die "phone: no iPhone with media control is connected"
}

module_open() {
  delight_run delight ui summon delight.phone '{}'
}
