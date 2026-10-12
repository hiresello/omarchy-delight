#!/bin/bash
# Syncthing REST client and status mapping for the sync module.
# Sourced by bin/delight-sync and the tests; needs curl + jq.

SYNC_CONFLICT_RE='\.sync-conflict-[0-9]{8}-[0-9]{6}-[A-Z2-7]{7}'

# config.xml location: Syncthing keeps using the legacy ~/.config dir when it
# already exists; 2.x otherwise defaults to the XDG state dir.
sync_config_file() {
  local dir
  for dir in "${STCONFDIR:-}" "${STHOMEDIR:-}" "${XDG_CONFIG_HOME:-$HOME/.config}/syncthing" \
    "${XDG_STATE_HOME:-$HOME/.local/state}/syncthing"; do
    if [[ -n $dir && -f $dir/config.xml ]]; then
      echo "$dir/config.xml"
      return 0
    fi
  done
  return 1
}

sync_api_key() {
  local file key
  file=$(sync_config_file) || return 1
  key=$(sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' "$file" | head -n 1)
  [[ -n $key ]] || return 1
  echo "$key"
}

sync_api_base() {
  echo "http://${SYNC_API_ADDRESS:-127.0.0.1:8384}"
}

# sync_api METHOD PATH [BODY] — prints the response body. Fails on transport
# errors and HTTP >= 400 (the body, Syncthing's error text, goes to stderr).
sync_api() {
  local method="$1" path="$2" body="${3-}" key out code
  local -a args=(-sS --max-time "${SYNC_API_TIMEOUT:-10}" -X "$method" -w '\n%{http_code}')
  key=${SYNC_API_KEY:-$(sync_api_key)} || {
    echo "sync: no Syncthing API key (has syncthing.service ever started?)" >&2
    return 1
  }
  args+=(-H "X-API-Key: $key")
  if [[ $# -ge 3 ]]; then
    args+=(-H "Content-Type: application/json" --data-binary "$body")
  fi
  out=$(curl "${args[@]}" "$(sync_api_base)$path") || return 1
  code=${out##*$'\n'}
  out=${out%$'\n'*}
  if [[ ! $code =~ ^2 ]]; then
    echo "sync: $method $path: HTTP $code${out:+: $out}" >&2
    return 1
  fi
  printf '%s\n' "$out"
}

sync_api_up() {
  SYNC_API_TIMEOUT=${SYNC_API_TIMEOUT:-3} sync_api GET /rest/noauth/health >/dev/null 2>&1
}

sync_wait_api() {
  local tries="${1:-30}"
  while ((tries-- > 0)); do
    if sync_api_up; then
      return 0
    fi
    sleep 1
  done
  return 1
}

sync_my_id() {
  sync_api GET /rest/system/status | jq -er '.myID'
}

# Accepts any spacing/case, with or without dashes; prints the canonical form.
sync_normalize_id() {
  local raw="${1^^}" plain
  plain=${raw//[^A-Z0-9]/}
  [[ $plain =~ ^[A-Z2-7]{56}$ ]] || return 1
  echo "$plain" | fold -w 7 | paste -sd- -
}

sync_expand_path() {
  local path="$1"
  case "$path" in
    "~") path=$HOME ;;
    \~/*) path=$HOME/${path:2} ;;
  esac
  [[ $path == /* ]] || path=$PWD/$path
  echo "${path%/}"
}

# Prints the device ID for a device ID or configured device name.
sync_resolve_device() {
  local want="$1" id
  if id=$(sync_normalize_id "$want"); then
    echo "$id"
    return 0
  fi
  id=$(sync_api GET /rest/config/devices | jq -r --arg n "${want,,}" \
    '[.[] | select((.name | ascii_downcase) == $n) | .deviceID][0] // empty') || return 1
  [[ -n $id ]] || {
    echo "sync: no device named '$want'" >&2
    return 1
  }
  echo "$id"
}

sync_add_device() {
  local id="$1" name="${2:-}" body
  id=$(sync_normalize_id "$id") || {
    echo "sync: '$1' is not a Syncthing device ID" >&2
    return 1
  }
  if [[ -z $name ]]; then
    name=$(sync_api GET /rest/cluster/pending/devices | jq -r --arg id "$id" '.[$id].name // empty') || name=""
  fi
  body=$(jq -cn --arg id "$id" --arg name "$name" '{deviceID:$id, name:$name, addresses:["dynamic"]}')
  sync_api POST /rest/config/devices "$body" >/dev/null
}

sync_share_folder() {
  local folder="$1" device="$2" devices
  devices=$(sync_api GET "/rest/config/folders/$folder" \
    | jq -c --arg d "$device" '{devices: ((.devices // []) + [{deviceID:$d}] | unique_by(.deviceID))}') || return 1
  sync_api PATCH "/rest/config/folders/$folder" "$devices" >/dev/null
}

sync_ignore_device() {
  local id="$1" config
  id=$(sync_normalize_id "$id") || {
    echo "sync: '$1' is not a Syncthing device ID" >&2
    return 1
  }
  config=$(sync_api GET /rest/config | jq -c --arg id "$id" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .remoteIgnoredDevices = ((.remoteIgnoredDevices // [])
      + [{deviceID:$id, name:"", address:"", time:$now}] | unique_by(.deviceID))') || return 1
  sync_api PUT /rest/config "$config" >/dev/null
  sync_api DELETE "/rest/cluster/pending/devices?device=$id" >/dev/null 2>&1 || true
}

# sync_folder_id_for PATH -> existing folder id for PATH, if any.
sync_folder_id_for() {
  sync_api GET /rest/config/folders | jq -r --arg p "$1" '[.[] | select((.path | rtrimstr("/")) == $p) | .id][0] // empty'
}

# sync_add_folder PATH [ID] [LABEL] [DEVICE] — creates (or reuses) the folder,
# optionally shared with DEVICE, and prints its id.
sync_add_folder() {
  local path="$1" id="${2:-}" label="${3:-}" device="${4:-}" existing body
  path=$(sync_expand_path "$path")
  existing=$(sync_folder_id_for "$path") || return 1
  if [[ -n $existing ]]; then
    if [[ -n $device ]]; then
      sync_share_folder "$existing" "$device" || return 1
    fi
    echo "$existing"
    return 0
  fi
  [[ -n $label ]] || label=$(basename -- "$path")
  if [[ -z $id ]]; then
    id=$(tr -cs 'a-z0-9' '-' <<<"${label,,}" | sed 's/^-*//;s/-*$//')
    id="${id:-folder}-$(tr -dc 'a-z0-9' </dev/urandom | head -c 5)"
  fi
  mkdir -p -- "$path"
  body=$(jq -cn --arg id "$id" --arg name "$label" --arg path "$path" --arg dev "$device" \
    '{"id":$id, "label":$name, "path":$path, "type":"sendreceive"}
      + if $dev == "" then {} else {devices:[{deviceID:$dev}]} end')
  sync_api POST /rest/config/folders "$body" >/dev/null || return 1
  echo "$id"
}

sync_conflicts_in() {
  local path="$1"
  [[ -d $path ]] || {
    echo 0
    return 0
  }
  find "$path" -path '*/.stversions' -prune -o -path '*/.stfolder' -prune -o \
    -type f -name '*.sync-conflict-*' -print 2>/dev/null | grep -cE "$SYNC_CONFLICT_RE" || true
}

# Everything the status mapping needs, as one JSON document.
sync_snapshot() {
  local config conns pending myid completion folders='{}' conflicts='{}' fid fpath n st
  myid=$(sync_my_id) || return 1
  config=$(sync_api GET /rest/config) || return 1
  conns=$(sync_api GET /rest/system/connections) || return 1
  pending=$(sync_api GET /rest/cluster/pending/devices) || pending='{}'
  completion=$(sync_api GET /rest/db/completion) || completion='{}'
  while IFS=$'\t' read -r fid fpath; do
    [[ -n $fid ]] || continue
    st=$(sync_api GET "/rest/db/status?folder=$fid") || st='{}'
    folders=$(jq -c --arg f "$fid" --argjson s "$st" '.[$f] = $s' <<<"$folders")
    n=$(sync_conflicts_in "$fpath")
    conflicts=$(jq -c --arg f "$fid" --argjson n "${n:-0}" '.[$f] = $n' <<<"$conflicts")
  done < <(jq -r '.folders[] | [.id, .path] | @tsv' <<<"$config")
  jq -cn --arg myid "$myid" --argjson config "$config" --argjson conns "$conns" \
    --argjson pending "$pending" --argjson completion "$completion" \
    --argjson folders "$folders" --argjson conflicts "$conflicts" \
    '{myID:$myid, config:$config, connections:$conns, pending:$pending,
      completion:$completion, folders:$folders, conflicts:$conflicts}'
}

# jq library shared by status and devices --json.
SYNC_JQ_DEFS='
def remotes: .myID as $me | [.config.devices[] | select(.deviceID != $me)];
def kind: (.name // "" | ascii_downcase) as $n
  | if ($n | test("ipad|tablet|tab ")) then "tablet"
    elif ($n | test("phone|pixel|android|galaxy|oneplus|xiaomi|fairphone|nothing")) then "phone"
    else "computer" end;
def devices: . as $s | [remotes[] | {
  id: .deviceID, name: (if (.name // "") == "" then .deviceID[0:7] else .name end),
  kind: kind, transport: "syncthing",
  connected: ($s.connections.connections[.deviceID].connected // false)}];
# `delight sync toggle` pauses every device (POST /rest/system/pause); a user
# may also pause every folder from the Syncthing GUI.
def paused: [.config.folders[]] as $f | remotes as $r
  | (($r | length) > 0 and ($r | all(.paused))) or (($f | length) > 0 and ($f | all(.paused)));
'

# Maps a snapshot (stdin) to {state,subtitle,reason,conflictFolder}.
sync_status_fields() {
  jq -c "$SYNC_JQ_DEFS"'
    . as $s
    | remotes as $r
    | [.config.folders[]] as $f
    | devices as $d
    | ([$d[] | select(.connected)] | length) as $up
    | ([.conflicts[]] | add // 0) as $nconf
    | (.pending | length) as $npend
    | ([$f[] | . as $x | ($s.folders[$x.id] // {}) | select(.state == "error")
        | ($x.label // $x.id)]) as $broken
    | ([$f[] | select(.paused | not) | $s.folders[.id] // {}]) as $active
    | ([$active[] | select(.state // "" | test("^sync"))] | length) as $syncing
    | ([$active[].globalBytes // 0] | add // 0) as $gb
    | ([$active[].needBytes // 0] | add // 0) as $nb
    | (if $gb > 0 then (($gb - $nb) * 100 / $gb | floor) else 100 end) as $local
    | (if $up > 0 then (.completion.completion // 100 | floor) else 100 end) as $remote
    | ([$local, $remote] | min) as $pct
    | paused as $paused
    | ([$f[] | select((($s.conflicts[.id]) // 0) > 0) | .path][0] // ($f[0].path // "")) as $cfolder
    | {conflictFolder: $cfolder, conflicts: $nconf, pending: $npend}
    + if ($broken | length) > 0 then
        {state:"error", subtitle:"Folder error", reason:("Syncthing reports an error in " + ($broken | join(", ")))}
      elif $paused then {state:"off", subtitle:"Paused"}
      elif $syncing > 0 or ($up > 0 and $pct < 100) then {state:"busy", subtitle:("Syncing \($pct)%")}
      elif $nconf > 0 then {state:"on", subtitle:(if $nconf == 1 then "1 conflict" else "\($nconf) conflicts" end)}
      elif $npend > 0 then {state:"on", subtitle:(if $npend == 1 then "1 device wants to pair" else "\($npend) devices want to pair" end)}
      elif ($r | length) == 0 then {state:"on", subtitle:"Ready to pair"}
      elif $up == 0 then {state:"on", subtitle:(if ($r | length) == 1 then "\($d[0].name) disconnected" else "Devices disconnected" end)}
      elif $up < ($r | length) then {state:"on", subtitle:"Up to date · \($up) of \($r | length) connected"}
      else {state:"on", subtitle:"Up to date"} end'
}

sync_devices_from() {
  jq -c "$SYNC_JQ_DEFS"'devices'
}
