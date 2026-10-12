#!/bin/bash

PHONE_SERVICE="org.kde.kdeconnect"
PHONE_ROOT_PATH="/modules/kdeconnect"
PHONE_DEVICE_ROOT="/modules/kdeconnect/devices"
PHONE_DAEMON_IFACE="org.kde.kdeconnect.daemon"
PHONE_DEVICE_IFACE="org.kde.kdeconnect.device"
PHONE_BATTERY_IFACE="org.kde.kdeconnect.device.battery"
PHONE_NOTIFICATIONS_IFACE="org.kde.kdeconnect.device.notifications"
PHONE_NOTIFICATION_IFACE="org.kde.kdeconnect.device.notifications.notification"
PHONE_CONVERSATIONS_IFACE="org.kde.kdeconnect.device.conversations"
PHONE_ICON="󰄜"
PHONE_APP_URL="https://kdeconnect.kde.org/download.html"

phone_bus() {
  busctl --user --json=short "$@" 2>/dev/null
}

phone_json_value() {
  local json="${1:-}"
  [[ -n $json ]] || json='{}'
  jq -r 'if type == "object" and has("data") then .data | if type == "array" then .[0] // empty else . end else empty end' \
    <<<"$json"
}

phone_json_data() {
  local json="${1:-}"
  [[ -n $json ]] || json='{}'
  jq -c '
    (.data // []) |
    if type == "array" and length == 1 and
      ((.[0] | type) == "array" or (.[0] | type) == "object") then .[0]
    else .
    end
  ' <<<"$json"
}

phone_daemon_call() {
  phone_bus call "$PHONE_SERVICE" "$PHONE_ROOT_PATH" "$PHONE_DAEMON_IFACE" "$@"
}

phone_daemon_available() {
  local result
  result=$(phone_daemon_call announcedName) || return 1
  jq -e 'has("data")' <<<"$result" >/dev/null
}

phone_daemon_property() {
  local property="$1" result
  result=$(phone_bus get-property "$PHONE_SERVICE" "$PHONE_ROOT_PATH" "$PHONE_DAEMON_IFACE" "$property") || return 1
  phone_json_value "$result"
}

phone_daemon_property_data() {
  local property="$1" result
  result=$(phone_bus get-property "$PHONE_SERVICE" "$PHONE_ROOT_PATH" "$PHONE_DAEMON_IFACE" "$property") || return 1
  phone_json_data "$result"
}

phone_device_valid() {
  [[ $1 =~ ^[A-Za-z0-9_]+$ ]]
}

phone_device_path() {
  printf '%s/%s\n' "$PHONE_DEVICE_ROOT" "$1"
}

phone_device_object_path() {
  local device="$1" interface="$2" suffix=""
  case "$interface" in
    "$PHONE_BATTERY_IFACE") suffix=battery ;;
    "$PHONE_NOTIFICATIONS_IFACE") suffix=notifications ;;
    org.kde.kdeconnect.device.clipboard) suffix=clipboard ;;
    org.kde.kdeconnect.device.share) suffix=share ;;
    org.kde.kdeconnect.device.findmyphone) suffix=findmyphone ;;
  esac
  if [[ -n $suffix ]]; then
    printf '%s/%s\n' "$(phone_device_path "$device")" "$suffix"
  else
    phone_device_path "$device"
  fi
}

phone_device_call() {
  local device="$1" interface="$2"
  shift 2
  phone_device_valid "$device" || return 1
  phone_bus call "$PHONE_SERVICE" "$(phone_device_object_path "$device" "$interface")" "$interface" "$@"
}

phone_device_property() {
  local device="$1" interface="$2" property="$3" result
  phone_device_valid "$device" || return 1
  result=$(phone_bus get-property "$PHONE_SERVICE" "$(phone_device_object_path "$device" "$interface")" "$interface" "$property") || return 1
  phone_json_value "$result"
}

phone_device_property_data() {
  local device="$1" interface="$2" property="$3" result
  phone_device_valid "$device" || return 1
  result=$(phone_bus get-property "$PHONE_SERVICE" "$(phone_device_object_path "$device" "$interface")" "$interface" "$property") || return 1
  phone_json_data "$result"
}

phone_device_ids() {
  local reachable="$1" paired="$2" result
  result=$(phone_daemon_call devices bb "$reachable" "$paired") || return 0
  phone_json_data "$result" | jq -r '.[]? | strings'
}

phone_daemon_names() {
  local reachable="$1" paired="$2" result
  result=$(phone_daemon_call deviceNames bb "$reachable" "$paired") || return 0
  phone_json_data "$result"
}

phone_name_from_map() {
  local id="$1" names="$2"
  jq -r --arg id "$id" '
    if type == "array" then
      (reduce .[] as $entry ({};
        if ($entry | type) == "array" then .[$entry[0]] = $entry[1]
        elif ($entry | type) == "object" and ($entry.data | type) == "array" and ($entry.data | length) >= 2 then
          .[$entry.data[0]] = $entry.data[1]
        elif ($entry | type) == "object" then
          reduce ($entry | to_entries[]) as $pair (.; .[$pair.key] = $pair.value)
        else . end
      ))[$id] // $id
    elif type == "object" then
      .[$id] // $id
    else
      $id
    end
  ' <<<"$names"
}

phone_device_name() {
  local id="$1" reachable="${2:-false}" paired="${3:-true}" names
  names=$(phone_daemon_names "$reachable" "$paired")
  phone_name_from_map "$id" "$names"
}

phone_device_plugins() {
  phone_device_property_data "$1" "$PHONE_DEVICE_IFACE" supportedPlugins || printf '[]\n'
}

phone_device_kind() {
  case "$1" in
    smartphone) printf 'phone\n' ;;
    tablet) printf 'tablet\n' ;;
    desktop | laptop | tv) printf 'computer\n' ;;
    *) printf 'phone\n' ;;
  esac
}

phone_device_json() {
  local id="$1" names="$2" name type kind reachable has_battery charge charging plugins limited battery
  name=$(phone_name_from_map "$id" "$names")
  type=$(phone_device_property "$id" "$PHONE_DEVICE_IFACE" type || true)
  kind=$(phone_device_kind "$type")
  reachable=$(phone_device_property "$id" "$PHONE_DEVICE_IFACE" isReachable || true)
  [[ $reachable == "true" ]] || reachable=false
  has_battery=$(phone_device_property "$id" "$PHONE_BATTERY_IFACE" hasBattery || true)
  if [[ $has_battery == "true" ]]; then
    charge=$(phone_device_property "$id" "$PHONE_BATTERY_IFACE" charge || true)
    charging=$(phone_device_property "$id" "$PHONE_BATTERY_IFACE" isCharging || true)
    [[ $charge =~ ^[0-9]+$ ]] || charge=0
    [[ $charging == "true" ]] || charging=false
    battery=$(jq -cn --argjson charge "$charge" --argjson charging "$charging" \
      '{charge:$charge,charging:$charging}')
  else
    battery=null
  fi
  plugins=$(phone_device_plugins "$id")
  limited=$(jq -cn --argjson plugins "$plugins" \
    'all($plugins[]; . != "kdeconnect_sms" and . != "kdeconnect_notifications")')
  jq -cn --arg id "$id" --arg name "$name" --arg kind "$kind" --argjson connected "$reachable" \
    --argjson battery "$battery" --argjson limited "$limited" \
    '{id:$id,name:$name,kind:$kind,transport:"kdeconnect",connected:$connected,battery:$battery,limited:$limited}'
}

phone_devices_json() {
  local names id
  names=$(phone_daemon_names false true)
  while IFS= read -r id; do
    [[ -n $id ]] || continue
    phone_device_json "$id" "$names"
  done < <(phone_device_ids false true) | jq -cs .
}

phone_share_plugin_loaded() {
  local result
  result=$(phone_device_call "$1" "$PHONE_DEVICE_IFACE" loadedPlugins) || return 1
  phone_json_data "$result" | jq -e 'index("kdeconnect_share") != null' >/dev/null
}

phone_share_targets_json() {
  local id name reachable names
  names=$(phone_daemon_names true true)
  while IFS= read -r id; do
    [[ -n $id ]] || continue
    reachable=$(phone_device_property "$id" "$PHONE_DEVICE_IFACE" isReachable || true)
    [[ $reachable == "true" ]] || continue
    phone_share_plugin_loaded "$id" || continue
    name=$(phone_name_from_map "$id" "$names")
    jq -cn --arg id "phone:$id" --arg target_label "$name" --arg icon "$PHONE_ICON" \
      '{id:$id,label:$target_label,icon:$icon,kind:"phone"}'
  done < <(phone_device_ids true true) | jq -cs .
}

phone_status_json() {
  local title state subtitle devices='[]' selected reachable=false actions
  title=$(delight_module_field phone '.name')
  devices=$(phone_devices_json)
  if ! delight_is_installed phone; then
    state=needs-setup
    subtitle="Not installed"
  elif ! delight_module_enabled; then
    state=off
    subtitle="Off"
  else
    state=on
    if ! phone_daemon_available; then
      subtitle="Starting…"
    elif [[ $(jq 'length' <<<"$devices") == "0" ]]; then
      subtitle="No phone paired"
    else
      selected=$(jq -c 'map(select(.connected)) | .[0] // empty' <<<"$devices")
      if [[ -z $selected ]]; then
        selected=$(jq -c '.[0]' <<<"$devices")
      fi
      reachable=$(jq -r '.connected' <<<"$selected")
      subtitle=$(jq -r '
        .name +
        (if .connected then
          (if .battery then " · " + (.battery.charge | tostring) + "%" +
            (if .battery.charging then " charging" else "" end) else "" end)
        else
          " · not connected"
        end) +
        (if .limited then " · files & clipboard only" else "" end)
      ' <<<"$selected")
    fi
  fi
  actions=$(jq -cn '[
    {label:"Open",command:["delight","phone","open"]},
    {label:"Pair",command:["delight","phone","pair"]}
  ]')
  if [[ $state == "on" && $reachable == "true" ]]; then
    actions=$(jq -cn --argjson actions "$actions" \
      '$actions + [{label:"Ring",command:["delight","phone","ring"]}]')
  fi
  delight_status_json --id phone --state "$state" --title "$title" --subtitle "$subtitle" \
    --icon "$PHONE_ICON" --toggle true --actions "$actions" --devices "$devices"
}

phone_private_addresses() {
  local raw
  raw=$(ip -4 -o addr show 2>/dev/null || true)
  jq -Rsc '
    split("\n") | map(try capture("(?<address>[0-9.]+)/[0-9]+").address catch empty) |
    map(select(test("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.)"))) |
    unique
  ' <<<"$raw"
}

phone_device_records() {
  local ids="$1" reachable="$2" paired="$3" names id name kind type
  names=$(phone_daemon_names "$reachable" "$paired")
  while IFS= read -r id; do
    [[ -n $id ]] || continue
    type=$(phone_device_property "$id" "$PHONE_DEVICE_IFACE" type || true)
    kind=$(phone_device_kind "$type")
    name=$(phone_name_from_map "$id" "$names")
    jq -cn --arg id "$id" --arg name "$name" --arg kind "$kind" \
      '{id:$id,name:$name,kind:$kind}'
  done <<<"$ids" | jq -cs .
}

phone_pair_json() {
  local name id addresses reachable_ids discoverable requests requests_ids request_id key request_rows='[]'
  name=$(phone_daemon_property announcedName || true)
  id=$(phone_daemon_property selfId || true)
  addresses=$(phone_private_addresses)
  reachable_ids=$(phone_device_ids true false || true)
  discoverable=$(phone_device_records "$reachable_ids" true false)
  requests=$(phone_daemon_property_data pairingRequests || printf '[]\n')
  requests_ids=$(jq -r '.[]? | strings' <<<"$requests")
  while IFS= read -r request_id; do
    [[ -n $request_id ]] || continue
    key=$(phone_device_property "$request_id" "$PHONE_DEVICE_IFACE" verificationKey || true)
    request_rows=$(jq -cn --argjson rows "$request_rows" --arg id "$request_id" \
      --arg name "$(phone_device_name "$request_id" false false)" --arg key "$key" \
      '$rows + [{id:$id,name:$name,verificationKey:$key}]')
  done <<<"$requests_ids"
  jq -cn --arg name "${name:-}" --arg id "${id:-}" --argjson addresses "$addresses" \
    --arg qr "$XDG_RUNTIME_DIR/omarchy-delight/phone/pair-qr.png" \
    --arg appUrl "$PHONE_APP_URL" --argjson discoverable "$discoverable" \
    --argjson requests "$request_rows" --argjson paired "$(phone_devices_json)" \
    '{name:$name,id:$id,addresses:$addresses,qr:$qr,appUrl:$appUrl,discoverable:$discoverable,requests:$requests,paired:$paired}'
}

phone_config_bool() {
  [[ $(delight_config_get phone "$1" 2>/dev/null || printf false) == "true" ]]
}

phone_set_plugin_enabled() {
  local id="$1" plugin="$2" enabled="$3"
  phone_device_call "$id" "$PHONE_DEVICE_IFACE" setPluginEnabled sb "$plugin" "$enabled" >/dev/null
}

phone_apply_device_settings() {
  local id clipboard notifications
  if phone_config_bool clipboard; then clipboard=true; else clipboard=false; fi
  if phone_config_bool notifications; then notifications=true; else notifications=false; fi
  while IFS= read -r id; do
    [[ -n $id ]] || continue
    phone_set_plugin_enabled "$id" kdeconnect_clipboard "$clipboard" || true
    phone_set_plugin_enabled "$id" kdeconnect_notifications "$notifications" || true
  done < <(phone_device_ids false true)
  return 0
}

phone_require_paired_device() {
  local requested="${1:-}" devices id
  devices=$(phone_devices_json)
  if [[ -n $requested ]]; then
    id=${requested#phone:}
    jq -e --arg id "$id" '.[] | select(.id == $id and .connected)' <<<"$devices" >/dev/null || {
      delight_die "phone: unknown or unreachable device '$requested'"
    }
  else
    id=$(jq -r 'map(select(.connected)) | .[0].id // empty' <<<"$devices")
    [[ -n $id ]] || delight_die "phone: no reachable paired phone; run: delight phone pair"
  fi
  printf '%s\n' "$id"
}

phone_absolute_existing_path() {
  local path="$1"
  [[ -e $path ]] || delight_die "phone: path does not exist: $path"
  realpath -- "$path"
}

phone_cache_file() {
  printf '%s/phone/sms/%s.jsonl\n' "$DELIGHT_RUNTIME_DIR" "$1"
}

phone_sms_loaded_file() {
  printf '%s/phone/sms/%s.loaded.json\n' "$DELIGHT_RUNTIME_DIR" "$1"
}

phone_sms_normalize() {
  jq -c '
    def unwrap:
      if type == "object" and has("data") and has("type") then (.data | unwrap)
      elif type == "array" then map(unwrap)
      else .
      end;
    def field($message; $key; $index):
      if ($message | type) == "array" then $message[$index]
      else $message[$key] end;
    def addr($item):
      if ($item | type) == "array" then $item[0]
      elif ($item | type) == "object" then ($item.address // $item.data[0] // "")
      else $item end;
    (unwrap | if type == "array" then . else [] end) |
    map(. as $message |
      (field($message; "type"; 4) // 0) as $type |
      {
        threadId: (field($message; "threadID"; 6) | tonumber? // 0),
        addresses: ((field($message; "addresses"; 2) // []) | map(addr(.))),
        body: (field($message; "body"; 1) // ""),
        date: (field($message; "date"; 3) | tonumber? // 0),
        "read": (((field($message; "read"; 5) // 0) | tonumber? // 0) != 0),
        "outgoing": (($type | tonumber? // 0) == 2)
      }
    ) | sort_by(.date) | reverse
  ' <<<"$1"
}

phone_sms_device() {
  local requested="${1:-}" devices id limited
  devices=$(phone_devices_json)
  if [[ -n $requested ]]; then
    id=${requested#phone:}
    jq -e --arg id "$id" '.[] | select(.id == $id)' <<<"$devices" >/dev/null || delight_die "phone: unknown device '$requested'"
  else
    id=$(jq -r 'map(select(.connected)) | .[0].id // empty' <<<"$devices")
    if [[ -z $id ]]; then
      id=$(jq -r '.[0].id // empty' <<<"$devices")
    fi
    [[ -n $id ]] || delight_die "phone: no paired Android phone"
  fi
  limited=$(jq -r --arg id "$id" '.[] | select(.id == $id) | .limited' <<<"$devices")
  if [[ $limited == "true" ]]; then
    delight_die "SMS needs the Android app" 3
  fi
  printf '%s\n' "$id"
}

phone_sms_list() {
  local device="$1" result
  phone_device_call "$device" "$PHONE_CONVERSATIONS_IFACE" requestAllConversationThreads >/dev/null || true
  result=$(phone_device_call "$device" "$PHONE_CONVERSATIONS_IFACE" activeConversations) || {
    printf '[]\n'
    return 0
  }
  phone_sms_normalize "$result"
}

phone_sms_cache_append() {
  local device="$1" message="$2" normalized cache
  normalized=$(phone_sms_normalize "$message" | jq -c '.[0] // empty')
  [[ -n $normalized ]] || return 0
  cache=$(phone_cache_file "$device")
  delight_mkdir "$(dirname -- "$cache")"
  printf '%s\n' "$normalized" >>"$cache"
}

phone_sms_mark_loaded() {
  local device="$1" thread_id="$2" count="$3" path loaded
  path=$(phone_sms_loaded_file "$device")
  loaded='{}'
  [[ -f $path ]] && loaded=$(jq -c 'if type == "object" then . else {} end' "$path" 2>/dev/null || printf '{}')
  loaded=$(jq -cn --argjson loaded "$loaded" --arg thread "$thread_id" --arg count "$count" \
    '$loaded + {($thread): $count}')
  delight_write "$path" <<<"$loaded"
}

phone_sms_call_reply() {
  phone_device_call "$1" "$PHONE_CONVERSATIONS_IFACE" replyToConversation xsav "$2" "$3" 0 >/dev/null
}

phone_notification_map_path() {
  printf '%s/phone/notifications.json\n' "$DELIGHT_RUNTIME_DIR"
}

phone_notification_map_read() {
  local path
  path=$(phone_notification_map_path)
  if [[ -f $path ]]; then
    jq -c 'if type == "object" then . else {} end' "$path" 2>/dev/null || printf '{}\n'
  else
    printf '{}\n'
  fi
}

phone_notification_map_write() {
  local json="$1" path
  path=$(phone_notification_map_path)
  delight_write "$path" <<<"$json"
}

phone_notification_path() {
  local device="$1" public_id="$2"
  phone_device_valid "$device" || return 1
  [[ $public_id =~ ^[A-Za-z0-9_]+$ ]] || return 1
  printf '%s/%s/notifications/%s\n' "$PHONE_DEVICE_ROOT" "$device" "$public_id"
}

phone_notification_property() {
  local object_path="$1" property="$2" result
  result=$(phone_bus get-property "$PHONE_SERVICE" "$object_path" "$PHONE_NOTIFICATION_IFACE" "$property") || return 1
  phone_json_value "$result"
}

phone_signal_value() {
  local index="$2"
  jq -r --argjson index "$index" '
    def unbox:
      if type == "object" and has("data") then (.data | unbox)
      elif type == "array" then map(unbox)
      else .
      end;
    ((.payload.data // .payload.args // .data // .args // []) | unbox)[$index] // empty | tostring
  ' <<<"$1"
}

phone_signal_data() {
  jq -c '.payload.data // .payload.args // .data // .args // []' <<<"$1"
}

phone_map_notification() {
  local device="$1" public_id="$2" app title text silent has_icon icon_path prior omarchy_id map key object_path
  local args=()
  object_path=$(phone_notification_path "$device" "$public_id") || return 0
  app=$(phone_notification_property "$object_path" appName || true)
  title=$(phone_notification_property "$object_path" title || true)
  text=$(phone_notification_property "$object_path" text || true)
  silent=$(phone_notification_property "$object_path" silent || true)
  [[ $silent != "true" ]] || return 0
  has_icon=$(phone_notification_property "$object_path" hasIcon || true)
  icon_path=$(phone_notification_property "$object_path" iconPath || true)
  key="$device/$public_id"
  map=$(phone_notification_map_read)
  prior=$(jq -r --arg key "$key" '.[$key] // empty' <<<"$map")
  if [[ -n $prior ]]; then
    args+=(-r "$prior")
  fi
  if [[ $has_icon == "true" && -n $icon_path ]]; then
    args+=(--image "$icon_path")
  fi
  omarchy_id=$(delight_notify phone "${app:-Phone}" "${title:-Notification}: ${text:-}" \
    -g "$PHONE_ICON" -p "${args[@]}" 2>/dev/null || true)
  if [[ $omarchy_id =~ ^[0-9]+$ ]]; then
    map=$(jq -cn --argjson map "$map" --arg key "$key" --arg id "$omarchy_id" '$map + {($key): $id}')
    phone_notification_map_write "$map"
  fi
}

phone_notification_close() {
  local device="$1" public_id="$2" key map id
  key="$device/$public_id"
  map=$(phone_notification_map_read)
  id=$(jq -r --arg key "$key" '.[$key] // empty' <<<"$map")
  [[ $id =~ ^[0-9]+$ ]] || return 0
  phone_bus call org.freedesktop.Notifications /org/freedesktop/Notifications \
    org.freedesktop.Notifications CloseNotification u "$id" >/dev/null || true
  map=$(jq -cn --argjson map "$map" --arg key "$key" '$map | del(.[$key])')
  phone_notification_map_write "$map"
}

phone_notification_close_device() {
  local device="$1" map key id
  map=$(phone_notification_map_read)
  while IFS=$'\t' read -r key id; do
    [[ -n $key && $id =~ ^[0-9]+$ ]] || continue
    phone_bus call org.freedesktop.Notifications /org/freedesktop/Notifications \
      org.freedesktop.Notifications CloseNotification u "$id" >/dev/null || true
    map=$(jq -cn --argjson map "$map" --arg key "$key" '$map | del(.[$key])')
  done < <(jq -r --arg prefix "$device/" 'to_entries[] | select(.key | startswith($prefix)) | [.key,.value] | @tsv' <<<"$map")
  phone_notification_map_write "$map"
}

phone_handle_closed_notification() {
  local notification_id="$1" reason="$2" map entry device public_id object_path
  [[ $reason == "2" ]] || return 0
  map=$(phone_notification_map_read)
  entry=$(jq -r --arg id "$notification_id" 'to_entries[] | select(.value == $id) | .key' <<<"$map" | head -n1)
  [[ -n $entry ]] || return 0
  device=${entry%%/*}
  public_id=${entry#*/}
  object_path=$(phone_notification_path "$device" "$public_id") || return 0
  phone_bus call "$PHONE_SERVICE" "$object_path" "$PHONE_NOTIFICATION_IFACE" dismiss >/dev/null || true
  map=$(jq -cn --argjson map "$map" --arg key "$entry" '$map | del(.[$key])')
  phone_notification_map_write "$map"
}

phone_pairing_requests_notify() {
  local requests current cache old request_id name
  requests=$(phone_daemon_property_data pairingRequests || printf '[]\n')
  current=$(jq -c 'if type == "array" then . else [] end' <<<"$requests")
  cache="$DELIGHT_RUNTIME_DIR/phone/pair-requests.json"
  old='[]'
  [[ -f $cache ]] && old=$(jq -c 'if type == "array" then . else [] end' "$cache" 2>/dev/null || printf '[]')
  while IFS= read -r request_id; do
    [[ -n $request_id ]] || continue
    if jq -e --arg id "$request_id" 'index($id) != null' <<<"$old" >/dev/null; then
      continue
    fi
    name=$(phone_device_name "$request_id" false false)
    delight_notify phone "Pair request" "$name wants to pair" --exec delight phone pair >/dev/null 2>&1 || true
  done < <(jq -r '.[]? | strings' <<<"$current")
  delight_mkdir "$(dirname -- "$cache")"
  delight_write "$cache" <<<"$current"
}

phone_handle_signal() {
  local signal="$1" member path interface device public_id data reason
  member=$(jq -r '.member // .signal // empty' <<<"$signal")
  path=$(jq -r '.path // empty' <<<"$signal")
  interface=$(jq -r '.interface // empty' <<<"$signal")
  device=$(sed -nE 's#^/modules/kdeconnect/devices/([^/]+)(/.*)?$#\1#p' <<<"$path")
  data=$(phone_signal_data "$signal")
  public_id=$(phone_signal_value "$signal" 0)
  case "$member" in
    notificationPosted | notificationUpdated)
      if phone_config_bool notifications && [[ -n $device ]]; then
        phone_map_notification "$device" "$public_id"
      fi
      ;;
    notificationRemoved)
      phone_notification_close "$device" "$public_id"
      ;;
    allNotificationsRemoved)
      phone_notification_close_device "$device"
      ;;
    NotificationClosed)
      reason=$(phone_signal_value "$signal" 1)
      phone_handle_closed_notification "$public_id" "$reason"
      ;;
    pairingRequestsChanged)
      phone_pairing_requests_notify
      ;;
    conversationCreated | conversationUpdated)
      if [[ -n $device ]]; then
        phone_sms_cache_append "$device" "$data"
      fi
      ;;
    conversationLoaded)
      if [[ -n $device ]]; then
        phone_sms_mark_loaded "$device" "$(phone_signal_value "$signal" 0)" \
          "$(phone_signal_value "$signal" 1)"
      fi
      ;;
    deviceAdded | deviceRemoved | deviceVisibilityChanged | deviceListChanged | reachableChanged | pairStateChanged | refreshed)
      phone_module_publish
      ;;
    *)
      if [[ $interface == "$PHONE_DEVICE_IFACE" || $interface == "$PHONE_BATTERY_IFACE" ]]; then
        phone_module_publish
      fi
      ;;
  esac
}

phone_module_publish() {
  local json
  json=$(phone_status_json) || return 0
  delight_status_write phone "$json"
}

phone_check_ufw() {
  local status proto cidr
  status=$(ufw status 2>/dev/null || true)
  for proto in tcp udp; do
    for cidr in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
      [[ $status == *"1714:1764/$proto"* && $status == *"$cidr"* && $status == *"omarchy-delight:phone"* ]] || return 1
    done
  done
  return 0
}

phone_doctor() {
  local rc=0 pkg unit log addresses devices user_notifyrc recorded_notifyrc entry
  addresses=$(phone_private_addresses)
  if [[ $(jq 'length' <<<"$addresses") == "0" ]]; then
    printf '%s\n' "unsupported: no private IPv4 network interface"
    return 2
  fi
  while IFS= read -r pkg; do
    [[ -n $pkg ]] || continue
    if ! delight_pkg_present "$pkg"; then
      printf 'missing package: %s (run: delight phone install)\n' "$pkg"
      rc=1
    fi
  done < <(delight_module_field phone '.packages.repo[]?, .packages.aur[]?')
  if [[ ${WAYLAND_DISPLAY:-} == "" || ${HYPRLAND_INSTANCE_SIGNATURE:-} == "" ]]; then
    printf '%s\n' "Hyprland Wayland session is unavailable"
    rc=1
  fi
  while IFS= read -r unit; do
    [[ -n $unit ]] || continue
    if ! systemctl --user is-active --quiet "$unit"; then
      printf 'inactive unit: %s (run: delight phone enable)\n' "$unit"
      rc=1
    fi
  done < <(delight_module_units)
  if ! phone_daemon_available; then
    printf '%s\n' "KDE Connect daemon is not on the session bus"
    rc=1
  fi
  if delight_has_cmd ufw && ! phone_check_ufw; then
    printf '%s\n' "KDE Connect firewall rules are missing (run: delight phone install)"
    rc=1
  fi
  if delight_has_cmd journalctl; then
    log=$(journalctl --user -u delight-phone.service --no-pager 2>/dev/null || true)
    if [[ $log == *"Could not init WaylandClipboard, falling back to QtClipboard."* ]]; then
      printf '%s\n' "KDE Connect fell back to QtClipboard; check Wayland data-control support"
      rc=1
    fi
  fi
  user_notifyrc="$HOME/.config/kdeconnect.notifyrc"
  recorded_notifyrc=false
  while IFS= read -r entry; do
    if jq -e --arg path "$user_notifyrc" '. == $path' <<<"$entry" >/dev/null 2>&1; then
      recorded_notifyrc=true
    fi
  done < <(delight_state_list phone files)
  if [[ -e $user_notifyrc && $recorded_notifyrc == "false" ]]; then
    printf '%s\n' "pre-existing kdeconnect.notifyrc may allow duplicate phone notifications"
    rc=1
  fi
  devices=$(phone_devices_json)
  if [[ $(jq 'length' <<<"$devices") == "0" ]]; then
    printf '%s\n' "no paired phone (run: delight phone pair)"
    if ((rc == 0)); then
      return 3
    fi
  fi
  if ((rc == 0)); then
    printf '%s\n' "ok"
  fi
  return "$rc"
}

phone_module_install() {
  local source destination recorded entry
  delight_module_default_install
  while IFS=$'\t' read -r source destination; do
    [[ -n $source && -n $destination ]] || continue
    recorded=false
    while IFS= read -r entry; do
      if jq -e --arg path "$destination" '. == $path' <<<"$entry" >/dev/null 2>&1; then
        recorded=true
      fi
    done < <(delight_state_list phone files)
    if [[ (-e $destination || -L $destination) && $recorded == "false" ]]; then
      delight_log "phone: preserving existing user file $destination"
    else
      delight_file_install phone "$DELIGHT_MODULES_DIR/phone/share/$source" "$destination"
    fi
  done <<EOF
org.kde.kdeconnect.daemon.desktop	$HOME/.config/autostart/org.kde.kdeconnect.daemon.desktop
org.kde.kdeconnect.service	$HOME/.local/share/dbus-1/services/org.kde.kdeconnect.service
kdeconnect.notifyrc	$HOME/.config/kdeconnect.notifyrc
EOF
}

module_install() {
  phone_module_install
}

module_enable() {
  delight_module_default_enable
  phone_apply_device_settings
}

module_disable() {
  delight_module_default_disable
  phone_apply_device_settings
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

module_share-targets() {
  [[ ${1:-} == "--json" ]] || delight_die "usage: delight phone share-targets --json" 64
  phone_share_targets_json
}

module_send() {
  (($# >= 2)) || delight_die "usage: delight phone send <target> <path|URL>..." 64
  local target="$1" id path
  shift
  id=$(phone_require_paired_device "$target")
  for path in "$@"; do
    if [[ $path =~ ^https?:// ]]; then
      delight_run kdeconnect-cli --share "$path" -d "$id"
    else
      path=$(phone_absolute_existing_path "$path")
      delight_run kdeconnect-cli --share "$path" -d "$id"
    fi
  done
}

module_ring() {
  local id
  id=$(phone_require_paired_device "${1:-}")
  delight_run kdeconnect-cli --ring -d "$id"
}

module_pair() {
  local action="${1:-}" id path payload
  case "$action" in
    --json)
      phone_pair_json
      ;;
    accept | reject | request)
      (($# == 2)) || delight_die "usage: delight phone pair $action <device-id>" 64
      id="$2"
      case "$action" in
        accept) phone_device_call "$id" "$PHONE_DEVICE_IFACE" acceptPairing >/dev/null ;;
        reject) phone_device_call "$id" "$PHONE_DEVICE_IFACE" cancelPairing >/dev/null ;;
        request) phone_device_call "$id" "$PHONE_DEVICE_IFACE" requestPairing >/dev/null ;;
      esac
      phone_module_publish
      ;;
    "")
      path="$XDG_RUNTIME_DIR/omarchy-delight/phone/pair-qr.png"
      delight_mkdir "$(dirname -- "$path")"
      delight_qr "$PHONE_APP_URL" "$path"
      payload=$(jq -cn '{view:"pair"}')
      delight_run delight ui summon delight.phone "$payload"
      ;;
    *)
      delight_die "usage: delight phone pair [--json|accept|reject|request <device-id>]" 64
      ;;
  esac
}

module_open() {
  local view="${1:-main}" payload
  [[ $view == "main" || $view == "pair" || $view == "sms" ]] || delight_die "unknown phone view: $view" 64
  payload=$(jq -cn --arg view "$view" '{view:$view}')
  delight_run delight ui summon delight.phone "$payload"
}

module_clipboard() {
  local action="${1:-}" id
  case "$action" in
    on | off)
      if [[ $action == "on" ]]; then
        delight_config_set phone clipboard true
      else
        delight_config_set phone clipboard false
      fi
      phone_apply_device_settings
      ;;
    send)
      while IFS= read -r id; do
        [[ -n $id ]] || continue
        [[ $(phone_device_property "$id" "$PHONE_DEVICE_IFACE" isReachable || true) == "true" ]] || continue
        phone_device_call "$id" org.kde.kdeconnect.device.clipboard sendClipboard >/dev/null || true
      done < <(phone_device_ids false true)
      ;;
    *)
      delight_die "usage: delight phone clipboard [on|off|send]" 64
      ;;
  esac
}

module_sms() {
  local action="${1:-}" device="" thread_id text cache attempt json=false
  shift || true
  if [[ $action == "open" ]]; then
    module_open sms
    return 0
  fi
  case "$action" in
    list)
      while (($# > 0)); do
        case "$1" in
          --json) json=true ;;
          --device)
            shift
            device="${1:-}"
            ;;
          *) delight_die "usage: delight phone sms list --json [--device id]" 64 ;;
        esac
        shift
      done
      [[ $json == "true" ]] || delight_die "usage: delight phone sms list --json [--device id]" 64
      device=$(phone_sms_device "$device")
      phone_sms_list "$device"
      ;;
    thread)
      (($# >= 2)) || delight_die "usage: delight phone sms thread <thread-id> --json [--device id]" 64
      thread_id="$1"
      shift
      json=false
      while (($# > 0)); do
        case "$1" in
          --json) json=true ;;
          --device)
            shift
            device="${1:-}"
            ;;
          *) delight_die "usage: delight phone sms thread <thread-id> --json [--device id]" 64 ;;
        esac
        shift
      done
      [[ $json == "true" ]] || delight_die "usage: delight phone sms thread <thread-id> --json [--device id]" 64
      device=$(phone_sms_device "$device")
      phone_device_call "$device" "$PHONE_CONVERSATIONS_IFACE" requestConversation xii "$thread_id" 0 50 >/dev/null || true
      cache=$(phone_cache_file "$device")
      if systemctl --user is-active --quiet delight-phone-bridge.service 2>/dev/null; then
        for ((attempt = 0; attempt < 20; attempt++)); do
          local loaded_file
          loaded_file=$(phone_sms_loaded_file "$device")
          if [[ -f $loaded_file ]] && jq -e --arg id "$thread_id" 'has($id)' "$loaded_file" >/dev/null 2>&1; then
            break
          fi
          sleep 0.1
        done
      fi
      if [[ -f $cache ]]; then
        jq -cs --arg id "$thread_id" \
          'map(select((.threadId | tostring) == $id)) | sort_by(.date) | reverse' "$cache"
      else
        printf '[]\n'
      fi
      ;;
    reply)
      (($# >= 2)) || delight_die "usage: delight phone sms reply <thread-id> <text>" 64
      thread_id="$1"
      text="$2"
      device=$(phone_sms_device)
      phone_sms_call_reply "$device" "$thread_id" "$text"
      ;;
    send)
      (($# >= 2)) || delight_die "usage: delight phone sms send <number> <text>" 64
      local number="$1"
      text="$2"
      device=$(phone_sms_device)
      phone_device_call "$device" "$PHONE_CONVERSATIONS_IFACE" sendWithoutConversation avsav \
        1 "(s)" "$number" "$text" 0 >/dev/null
      ;;
    *)
      delight_die "usage: delight phone sms {list|thread|reply|send|open}" 64
      ;;
  esac
}

module_watch() {
  local line
  while IFS= read -r line; do
    jq -e . <<<"$line" >/dev/null 2>&1 || continue
    phone_handle_signal "$line"
  done < <(stdbuf -oL busctl --user --json=short monitor "$PHONE_SERVICE" org.freedesktop.Notifications 2>/dev/null)
}

module_handle-signal() {
  (($# == 1)) || delight_die "usage: delight phone handle-signal <json>" 64
  phone_handle_signal "$1"
}
