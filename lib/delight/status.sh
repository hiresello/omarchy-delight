#!/bin/bash

# Status JSON (schema/status.schema.json). Modules print it from
# `status --json` and write it to $XDG_RUNTIME_DIR/omarchy-delight/status/<id>.json
# on every change; the Control Center draws one tile per file.

# delight_status_json --id ID --state STATE --title T [--subtitle S] [--icon I]
#   [--toggle true|false] [--reason R] [--actions JSON] [--devices JSON]
delight_status_json() {
  local id="" state="" title="" subtitle="" icon="" toggle=true reason="" actions='[]' devices='[]'
  while (($# > 0)); do
    case "$1" in
      --id) id="$2" ;;
      --state) state="$2" ;;
      --title) title="$2" ;;
      --subtitle) subtitle="$2" ;;
      --icon) icon="$2" ;;
      --toggle) toggle="$2" ;;
      --reason) reason="$2" ;;
      --actions) actions="$2" ;;
      --devices) devices="$2" ;;
      *) delight_die "delight_status_json: unknown option $1" ;;
    esac
    shift 2
  done
  jq -cn --arg id "$id" --arg state "$state" --arg title "$title" --arg subtitle "$subtitle" \
    --arg icon "$icon" --argjson toggle "$toggle" --arg reason "$reason" \
    --argjson actions "$actions" --argjson devices "$devices" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
      schema: 1, id: $id, state: $state, title: $title, subtitle: $subtitle, icon: $icon,
      toggle: $toggle, actions: $actions, devices: $devices,
      reason: (if $reason == "" then null else $reason end), updated: $updated
    }'
}

delight_status_file() {
  printf '%s/%s.json\n' "$DELIGHT_STATUS_DIR" "$1"
}

# delight_status_write <id> <json>
delight_status_write() {
  local id="$1" json="$2" tmp
  jq -e --arg id "$id" 'type == "object" and .id == $id' <<<"$json" >/dev/null \
    || delight_die "$id: status JSON must be an object with id \"$id\""
  if delight_dry; then
    delight_dry_print write-status "$id"
    return 0
  fi
  mkdir -p -- "$DELIGHT_STATUS_DIR"
  tmp=$(mktemp -p "$DELIGHT_STATUS_DIR" ".$id.XXXXXX")
  printf '%s\n' "$json" >"$tmp"
  mv -f -- "$tmp" "$(delight_status_file "$id")"
}

delight_status_clear() {
  delight_rm "$(delight_status_file "$1")"
}
