#!/bin/bash

# delight_notify <id> <title> <body> [extra omarchy-notification-send args...]
delight_notify() {
  local id="$1" title="$2" body="${3:-}"
  shift 3 || shift $#
  if delight_has_cmd omarchy-notification-send; then
    delight_run omarchy-notification-send --app-name "omarchy-delight-$id" "$@" "$title" "$body"
  elif delight_has_cmd notify-send; then
    delight_run notify-send -a "omarchy-delight-$id" "$title" "$body"
  else
    delight_log "$id: $title${body:+ — $body}"
  fi
}
