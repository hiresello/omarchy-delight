#!/bin/bash

hotspot_bt_adapter() {
  local adapter
  adapter=$(delight_config_get hotspot adapter)
  if [[ -n $adapter ]]; then
    printf '%s\n' "${adapter##*/}"
    return 0
  fi
  for adapter in "${DELIGHT_SYSFS:-/sys}"/class/bluetooth/hci*; do
    [[ -e $adapter ]] || continue
    basename -- "$adapter"
    return 0
  done
  return 1
}

hotspot_bt_device_path() {
  local adapter="$1" mac="${2//:/_}"
  printf '/org/bluez/%s/dev_%s\n' "$adapter" "$mac"
}

hotspot_bt_property() {
  local adapter="$1" mac="$2" interface="$3" property="$4" path value
  if [[ -n $mac ]]; then
    path=$(hotspot_bt_device_path "$adapter" "$mac")
  else
    path="/org/bluez/$adapter"
  fi
  value=$(timeout 2 busctl get-property org.bluez "$path" "org.bluez.$interface" "$property" 2>/dev/null) \
    || return 1
  case "$value" in
    "b "*) printf '%s\n' "${value#b }" ;;
    "n "*) printf '%s\n' "${value#n }" ;;
    "s "*) jq -r . <<<"${value#s }" ;;
    *) return 1 ;;
  esac
}

hotspot_bt_adapter_powered() {
  hotspot_bt_property "$1" "" Adapter1 Powered
}

hotspot_bt_connected() {
  hotspot_bt_property "$2" "$1" Device1 Connected | grep -qx true
}

hotspot_bt_alias() {
  hotspot_bt_property "$(hotspot_bt_adapter)" "$1" Device1 Alias
}

hotspot_bt_read_rssi() {
  hotspot_bt_property "$2" "$1" Device1 RSSI
}

hotspot_bt_scan_rssi() {
  local mac="$1" adapter="$2" window="$3" index pid value max=""
  if delight_dry; then
    delight_run timeout "$((window + 3))" bluetoothctl --timeout "$window" scan on
    return 0
  fi
  delight_run timeout "$((window + 3))" bluetoothctl --timeout "$window" scan on >/dev/null 2>&1 &
  pid=$!
  for ((index = 0; index < window; index++)); do
    value=$(hotspot_bt_read_rssi "$mac" "$adapter" || true)
    if [[ $value =~ ^-?[0-9]+$ ]] && { [[ -z $max ]] || ((value > max)); }; then
      max=$value
    fi
    sleep "${DELIGHT_HOTSPOT_POLL_SLEEP:-1}"
  done
  wait "$pid" || true
  [[ -n $max ]] && printf '%s\n' "$max"
}

hotspot_bt_paired_output() {
  local output=""
  command -v bluetoothctl >/dev/null 2>&1 || return 0
  output=$(timeout 2 bluetoothctl devices Paired 2>/dev/null) || output=""
  if [[ -z $output ]]; then
    output=$(timeout 2 bluetoothctl paired-devices 2>/dev/null) || output=""
  fi
  printf '%s\n' "$output"
}

hotspot_bt_devices_json() {
  local output line mac name connected icon phone global result='[]' lower
  output=$(hotspot_bt_paired_output)
  global=$(DELIGHT_HOTSPOT_COLLECTING_DEVICES=1 "$DELIGHT_ROOT/bin/delight" devices --json 2>/dev/null || printf '[]')
  while IFS= read -r line; do
    [[ $line == Device\ * ]] || continue
    read -r _ mac name <<<"$line"
    [[ $mac =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] || continue
    name=${line#Device "$mac"}
    name=${name# }
    connected=false
    hotspot_bt_connected "$mac" "$(hotspot_bt_adapter 2>/dev/null || true)" && connected=true
    icon=$(hotspot_bt_property "$(hotspot_bt_adapter 2>/dev/null || true)" "$mac" Device1 Icon || true)
    phone=false
    [[ $icon == phone ]] && phone=true
    lower=${mac,,}
    if [[ $phone != true ]] && jq -e --arg mac "$lower" \
      'any(.[]; ((.mac // "" | ascii_downcase) == $mac) and ((.module // "") != "hotspot"))' \
      <<<"$global" >/dev/null 2>&1; then
      phone=true
      name=$(jq -r --arg mac "$lower" '.[] | select((.mac // "" | ascii_downcase) == $mac and (.module // "") != "hotspot") | .name' <<<"$global" | head -n1)
    fi
    result=$(jq -c --arg mac "$mac" --arg name "$name" --argjson connected "$connected" \
      --argjson phone "$phone" '. + [{mac:$mac,name:$name,connected:$connected,phone:$phone}]' <<<"$result")
  done <<<"$output"
  printf '%s\n' "$result"
}

hotspot_candidates() {
  local ssids devices mac selected_ssid selected_mac
  ssids=$(hotspot_candidates_ssids)
  devices=$(hotspot_bt_devices_json)
  selected_ssid=$(delight_config_get hotspot ssid)
  selected_mac=$(delight_config_get hotspot phone.mac)
  jq -cn --argjson ssids "$ssids" --argjson devices "$devices" \
    --arg ssid "$selected_ssid" --arg mac "$selected_mac" \
    '{ssids:$ssids,devices:$devices,selected:{ssid:(if $ssid == "" then null else $ssid end),mac:(if $mac == "" then null else $mac end)}}'
}
