#!/bin/bash

hotspot_nm_run() {
  local wait="$1"
  shift
  if delight_dry; then
    delight_dry_print nmcli "$@"
  else
    delight_run_quiet timeout "$wait" nmcli "$@"
  fi
}

hotspot_nm_parse_row() {
  local raw="$1" field="" char escaped=false i
  local -a columns=()
  for ((i = 0; i < ${#raw}; i++)); do
    char=${raw:i:1}
    if [[ $escaped == true ]]; then
      field+="$char"
      escaped=false
    elif [[ $char == $'\\' ]]; then
      escaped=true
    elif [[ $char == : ]]; then
      columns+=("$field")
      field=""
    else
      field+="$char"
    fi
  done
  [[ $escaped == true ]] && field+=$'\\'
  columns+=("$field")
  ((${#columns[@]} >= 3)) || return 0
  jq -cn --arg name "${columns[0]}" --arg uuid "${columns[1]}" --arg type "${columns[2]}" \
    '{name:$name,uuid:$uuid,type:$type}'
}

hotspot_nm_parse_pair() {
  local raw="$1" field="" char escaped=false i
  local -a columns=()
  for ((i = 0; i < ${#raw}; i++)); do
    char=${raw:i:1}
    if [[ $escaped == true ]]; then
      field+="$char"
      escaped=false
    elif [[ $char == $'\\' ]]; then
      escaped=true
    elif [[ $char == : ]]; then
      columns+=("$field")
      field=""
    else
      field+="$char"
    fi
  done
  [[ $escaped == true ]] && field+=$'\\'
  columns+=("$field")
  ((${#columns[@]} >= 2)) || return 0
  jq -cn --arg first "${columns[0]}" --arg second "${columns[1]}" \
    '{first:$first,second:$second}'
}

hotspot_nm_connections_json() {
  local output line row result='[]'
  command -v nmcli >/dev/null 2>&1 || {
    printf '[]\n'
    return 0
  }
  output=$(timeout 2 nmcli -t -f NAME,UUID,TYPE connection show 2>/dev/null) || {
    printf '[]\n'
    return 0
  }
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    row=$(hotspot_nm_parse_row "$line")
    [[ -n $row ]] || continue
    result=$(jq -c --argjson row "$row" '. + [$row]' <<<"$result")
  done <<<"$output"
  printf '%s\n' "$result"
}

hotspot_nm_connection_uuids() {
  hotspot_nm_connections_json | jq -r '.[].uuid'
}

hotspot_nm_connection_exists() {
  local uuid="$1"
  hotspot_nm_connections_json | jq -e --arg uuid "$uuid" 'any(.[]; .uuid == $uuid)' >/dev/null
}

hotspot_nm_field() {
  local uuid="$1" field="$2"
  timeout 2 nmcli -g "$field" connection show uuid "$uuid" 2>/dev/null
}

hotspot_nm_active_uuids() {
  timeout 2 nmcli -t -f UUID connection show --active 2>/dev/null
}

hotspot_nm_is_active() {
  local uuid="$1"
  local active
  while IFS= read -r active; do
    [[ $active == "$uuid" ]] && return 0
  done < <(hotspot_nm_active_uuids)
  return 1
}

hotspot_nm_resolve_ssid() {
  local wanted="$1" row uuid name type ssid
  local rows
  rows=$(hotspot_nm_connections_json)
  while IFS= read -r row; do
    type=$(jq -r .type <<<"$row")
    [[ $type == 802-11-wireless ]] || continue
    uuid=$(jq -r .uuid <<<"$row")
    ssid=$(hotspot_nm_field "$uuid" 802-11-wireless.ssid) || continue
    if [[ $ssid == "$wanted" ]]; then
      jq -cn --arg uuid "$uuid" --arg name "$(jq -r .name <<<"$row")" --arg ssid "$ssid" \
        '{uuid:$uuid,name:$name,ssid:$ssid}'
      return 0
    fi
  done < <(jq -c '.[]' <<<"$rows")
  while IFS= read -r row; do
    type=$(jq -r .type <<<"$row")
    name=$(jq -r .name <<<"$row")
    [[ $type == 802-11-wireless && $name == "$wanted" ]] || continue
    uuid=$(jq -r .uuid <<<"$row")
    ssid=$(hotspot_nm_field "$uuid" 802-11-wireless.ssid) || ssid="$wanted"
    jq -cn --arg uuid "$uuid" --arg name "$name" --arg ssid "$ssid" \
      '{uuid:$uuid,name:$name,ssid:$ssid}'
    return 0
  done < <(jq -c '.[]' <<<"$rows")
  return 1
}

hotspot_nm_previous() {
  local uuid="$1" autoconnect priority metered
  autoconnect=$(hotspot_nm_field "$uuid" connection.autoconnect) || autoconnect=no
  priority=$(hotspot_nm_field "$uuid" connection.autoconnect-priority) || priority=0
  metered=$(hotspot_nm_field "$uuid" connection.metered) || metered=unknown
  jq -cn --arg autoconnect "$autoconnect" --arg priority "$priority" --arg metered "$metered" \
    '{autoconnect:$autoconnect,priority:$priority,metered:$metered}'
}

hotspot_nm_priority() {
  local uuid="$1" other value minimum=""
  while IFS= read -r other; do
    [[ -n $other && $other != "$uuid" ]] || continue
    value=$(hotspot_nm_field "$other" connection.autoconnect-priority) || value=0
    [[ $value =~ ^-?[0-9]+$ ]] || value=0
    if [[ -z $minimum ]] || ((value < minimum)); then
      minimum=$value
    fi
  done < <(hotspot_nm_connection_uuids)
  [[ -n $minimum ]] || minimum=0
  if ((minimum <= -998)); then
    printf '%s\n' -999
  else
    printf '%s\n' "$((minimum - 1))"
  fi
}

hotspot_nm_modify() {
  local uuid="$1" autoconnect="$2" priority="$3" metered="$4"
  hotspot_nm_run 5 connection modify uuid "$uuid" connection.autoconnect "$autoconnect" \
    connection.autoconnect-priority "$priority" connection.metered "$metered"
}

hotspot_nm_up() {
  hotspot_nm_run 45 connection up uuid "$1"
}

hotspot_nm_rescan() {
  hotspot_nm_run 5 device wifi rescan ssid "$1"
}

hotspot_nm_radio_enabled() {
  [[ $(timeout 2 nmcli radio wifi 2>/dev/null) == enabled ]]
}

hotspot_nm_online() {
  local uuid="$1" row type state
  if hotspot_nm_is_active "$uuid"; then
    return 0
  fi
  while IFS= read -r row; do
    type=${row%%:*}
    state=${row#*:}
    if [[ $type == wifi || $type == ethernet ]] && [[ $state == connected* ]]; then
      return 0
    fi
  done < <(timeout 2 nmcli -t -f TYPE,STATE device 2>/dev/null)
  return 1
}

hotspot_nm_create_interactive() {
  hotspot_nm_run 45 --ask device wifi connect "$1" name "$1"
}

hotspot_nm_restore() {
  local state uuid created prev autoconnect priority metered
  state=$(delight_state_flag_get hotspot nm)
  [[ -n $state ]] || return 0
  uuid=$(jq -r '.uuid // empty' <<<"$state")
  created=$(jq -r '.created // false' <<<"$state")
  prev=$(jq -c '.prev // {}' <<<"$state")
  [[ -n $uuid ]] || return 0
  if hotspot_nm_connection_exists "$uuid"; then
    if [[ $created == true ]]; then
      hotspot_nm_run 5 connection delete uuid "$uuid"
    else
      autoconnect=$(jq -r '.autoconnect // "no"' <<<"$prev")
      priority=$(jq -r '.priority // "0"' <<<"$prev")
      metered=$(jq -r '.metered // "unknown"' <<<"$prev")
      hotspot_nm_modify "$uuid" "$autoconnect" "$priority" "$metered"
    fi
  fi
  delight_state_update hotspot 'del(.flags.nm)'
}

hotspot_nm_candidates() {
  local rows result='[]' row uuid type ssid active
  rows=$(hotspot_nm_connections_json)
  while IFS= read -r row; do
    type=$(jq -r .type <<<"$row")
    [[ $type == 802-11-wireless ]] || continue
    uuid=$(jq -r .uuid <<<"$row")
    ssid=$(hotspot_nm_field "$uuid" 802-11-wireless.ssid) || continue
    [[ -n $ssid ]] || continue
    active=false
    hotspot_nm_is_active "$uuid" && active=true
    result=$(jq -c --arg ssid "$ssid" --arg uuid "$uuid" --argjson active "$active" \
      '. + [{ssid:$ssid,saved:true,uuid:$uuid,signal:null,active:$active}]' <<<"$result")
  done < <(jq -c '.[]' <<<"$rows")
  printf '%s\n' "$result"
}

hotspot_nm_scanned_candidates() {
  local output line row ssid signal result='[]'
  output=$(timeout 2 nmcli -t -f SSID,SIGNAL device wifi list --rescan no 2>/dev/null) || {
    printf '[]\n'
    return 0
  }
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    row=$(hotspot_nm_parse_pair "$line")
    [[ -n $row ]] || continue
    ssid=$(jq -r .first <<<"$row")
    signal=$(jq -r .second <<<"$row")
    [[ -n $ssid && $signal =~ ^[0-9]+$ ]] || continue
    result=$(jq -c --arg ssid "$ssid" --argjson signal "$signal" \
      '. + [{ssid:$ssid,saved:false,uuid:null,signal:$signal,active:false}]' <<<"$result")
  done <<<"$output"
  printf '%s\n' "$result"
}

hotspot_candidates_ssids() {
  local saved scan
  saved=$(hotspot_nm_candidates)
  scan=$(hotspot_nm_scanned_candidates)
  jq -cn --argjson saved "$saved" --argjson scan "$scan" \
    '($saved + $scan) | group_by(.ssid) | map(sort_by((if .saved then 0 else 1 end), (-(.signal // 0)))[0]) | sort_by((if .saved then 0 else 1 end), (-(.signal // 0)))'
}
