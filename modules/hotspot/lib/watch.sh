#!/bin/bash

hotspot_runtime_dir() {
  printf '%s/hotspot\n' "$DELIGHT_RUNTIME_DIR"
}

hotspot_proximity_file() {
  printf '%s/proximity.json\n' "$(hotspot_runtime_dir)"
}

hotspot_autojoin_file() {
  printf '%s/autojoin.json\n' "$(hotspot_runtime_dir)"
}

hotspot_write_runtime_json() {
  local file="$1" json="$2"
  printf '%s\n' "$json" | delight_write "$file"
}

hotspot_battery_paused() {
  local root="${DELIGHT_SYSFS:-/sys}/class/power_supply" path type present status capacity online threshold
  threshold=$(delight_config_get hotspot scan.pauseBelowBattery)
  [[ $threshold =~ ^[0-9]+$ ]] || threshold=20
  ((threshold > 0)) || return 1
  local mains=false discharging=false low=false
  for path in "$root"/*; do
    [[ -d $path ]] || continue
    type=$(cat -- "$path/type" 2>/dev/null || true)
    if [[ $type == Mains ]]; then
      online=$(cat -- "$path/online" 2>/dev/null || true)
      [[ $online == 1 ]] && mains=true
    fi
  done
  [[ $mains == false ]] || return 1
  for path in "$root"/*; do
    [[ -d $path ]] || continue
    type=$(cat -- "$path/type" 2>/dev/null || true)
    [[ $type == Battery ]] || continue
    present=$(cat -- "$path/present" 2>/dev/null || true)
    [[ $present == 1 ]] || continue
    [[ $(cat -- "$path/scope" 2>/dev/null || true) == Device ]] && continue
    status=$(cat -- "$path/status" 2>/dev/null || true)
    [[ $status == Charging || $status == Full ]] && continue
    discharging=true
    capacity=$(cat -- "$path/capacity" 2>/dev/null || true)
    [[ $capacity =~ ^[0-9]+$ ]] && ((capacity < threshold)) && low=true
  done
  [[ $discharging == true && $low == true ]]
}

hotspot_publish() {
  local json
  json=$(hotspot_status)
  delight_status_write hotspot "$json"
}

hotspot_proximity_set_paused() {
  local now="$1" file state
  file=$(hotspot_proximity_file)
  state='{"presence":"paused","since":null,"pending":null,"pendingSince":null,"smoothed":null,"rssi":null,"connected":false,"lastAt":null,"changed":false,"from":null}'
  if [[ -f $file ]]; then
    state=$(jq '.presence = "paused" | .pending = null | .pendingSince = null | .changed = false | .lastAt = null' "$file")
  fi
  hotspot_write_runtime_json "$file" "$state"
  hotspot_publish
  : "$now"
}

hotspot_proximity_set_unknown() {
  local file="$1" state
  state='{"presence":"unknown","since":null,"pending":null,"pendingSince":null,"smoothed":null,"rssi":null,"connected":false,"lastAt":null,"changed":false,"from":null}'
  hotspot_write_runtime_json "$file" "$state"
}

hotspot_hint_transition() {
  local from="$1" to="$2" phone
  phone=$(delight_config_get hotspot phone.name)
  if [[ $from == near && $to == away ]]; then
    case "$(delight_config_get hotspot hints.away)" in
      notify)
        if delight_has_cmd omarchy-notification-send; then
          delight_run omarchy-notification-send --app-name omarchy-delight-hotspot \
            "Lock now?" "$phone left" --exec delight hotspot lock-now
        else
          delight_notify hotspot "Lock now?" "$phone left"
        fi
        ;;
      lock)
        if ! omarchy-hyprland-session-locked 2>/dev/null; then
          hotspot_lock
        fi
        ;;
    esac
  elif [[ $from == away && $to == near ]]; then
    case "$(delight_config_get hotspot hints.return)" in
      notify) delight_notify hotspot "Welcome back" "$phone is nearby" ;;
      wake)
        if delight_has_cmd omarchy-brightness-display; then
          delight_run omarchy-brightness-display on
        else
          delight_run hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })'
        fi
        ;;
    esac
  fi
}

hotspot_backoff_reset() {
  hotspot_write_runtime_json "$(hotspot_autojoin_file)" '{"attempts":0,"backoff":0,"nextAttempt":0,"last":null}'
}

hotspot_autojoin_step() {
  local now="$1" presence="$2" uuid="$3" state attempts backoff next initial maximum ssid name
  [[ $(delight_config_get hotspot autoJoin) == true ]] || return 0
  if hotspot_nm_online "$uuid"; then
    hotspot_backoff_reset
    return 0
  fi
  [[ $presence == near ]] || return 0
  hotspot_nm_radio_enabled || return 0
  state='{"attempts":0,"backoff":0,"nextAttempt":0,"last":null}'
  [[ -f $(hotspot_autojoin_file) ]] && state=$(<"$(hotspot_autojoin_file)")
  next=$(jq -r '.nextAttempt // 0' <<<"$state")
  ((now >= next)) || return 0
  ssid=$(delight_config_get hotspot ssid)
  name=$(delight_config_get hotspot phone.name)
  hotspot_nm_rescan "$ssid" || true
  if hotspot_nm_up "$uuid"; then
    delight_notify hotspot "Connected to $name's hotspot" "$ssid"
    hotspot_backoff_reset
    return 0
  fi
  attempts=$(jq -r '.attempts // 0' <<<"$state")
  backoff=$(jq -r '.backoff // 0' <<<"$state")
  initial=$(delight_config_get hotspot backoff.initial)
  maximum=$(delight_config_get hotspot backoff.max)
  if ((attempts == 0)); then
    backoff=$initial
  else
    backoff=$((backoff * 2))
    ((backoff <= maximum)) || backoff=$maximum
  fi
  attempts=$((attempts + 1))
  next=$((now + backoff))
  hotspot_write_runtime_json "$(hotspot_autojoin_file)" \
    "$(jq -cn --argjson attempts "$attempts" --argjson backoff "$backoff" --argjson next "$next" --argjson now "$now" \
      '{attempts:$attempts,backoff:$backoff,nextAttempt:$next,last:$now}')"
}

hotspot_sample() {
  local mac="$1" adapter="$2" connected rssi="" window
  connected=$(hotspot_bt_connected "$mac" "$adapter" && echo 1 || echo 0)
  if [[ $connected == 1 && $(delight_config_get hotspot proximity.connectedIsNear) == true ]]; then
    :
  elif [[ $(delight_config_get hotspot proximity.method) == connect ]]; then
    if [[ $connected == 0 ]]; then
      if delight_dry; then
        delight_run timeout 10 bluetoothctl connect "$mac" >&2
      elif delight_run_quiet timeout 10 bluetoothctl connect "$mac"; then
        connected=1
      fi
    fi
  else
    window=$(delight_config_get hotspot scan.window)
    rssi=$(hotspot_bt_scan_rssi "$mac" "$adapter" "$window" || true)
  fi
  printf '%s\t%s\n' "$rssi" "$connected"
}

hotspot_watch_iteration() {
  local now="${DELIGHT_HOTSPOT_NOW:-$(date +%s)}" file adapter mac connected rssi sample params next from to state presence uuid
  file=$(hotspot_proximity_file)
  if [[ -z $(delight_config_get hotspot phone.mac) || -z $(delight_config_get hotspot connection) ]] \
    || ! delight_module_enabled; then
    hotspot_publish
    return 0
  fi
  if hotspot_battery_paused; then
    hotspot_proximity_set_paused "$now"
    return 0
  fi
  if ! delight_hw_bluetooth; then
    hotspot_proximity_set_unknown "$file"
    hotspot_publish
    return 0
  fi
  adapter=$(hotspot_bt_adapter) || {
    hotspot_proximity_set_unknown "$file"
    hotspot_publish
    return 0
  }
  if [[ $(hotspot_bt_adapter_powered "$adapter" || true) != true ]]; then
    hotspot_proximity_set_unknown "$file"
    hotspot_publish
    return 0
  fi
  mac=$(delight_config_get hotspot phone.mac)
  sample=$(hotspot_sample "$mac" "$adapter")
  rssi=${sample%%$'\t'*}
  connected=${sample#*$'\t'}
  state=""
  [[ -f $file ]] && state=$(<"$file")
  [[ -n $state ]] || state='{}'
  if [[ $(jq -r '.presence // "unknown"' <<<"$state") == paused ]]; then
    state='{"presence":"unknown"}'
  fi
  params=$(hotspot_prox_params)
  next=$(hotspot_prox_step "$state" "$now" "$rssi" "$connected" "$params")
  hotspot_write_runtime_json "$file" "$next"
  if [[ $(jq -r .changed <<<"$next") == true ]]; then
    from=$(jq -r .from <<<"$next")
    to=$(jq -r .presence <<<"$next")
    hotspot_publish
    hotspot_hint_transition "$from" "$to"
  else
    hotspot_publish
  fi
  presence=$(jq -r .presence <<<"$next")
  uuid=$(delight_config_get hotspot connection)
  hotspot_autojoin_step "$now" "$presence" "$uuid"
}
