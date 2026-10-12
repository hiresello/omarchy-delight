#!/bin/bash

# Pure helpers for the sidecar module: presets, monitor-rule generation and
# Sunshine override rendering. No side effects; unit-tested in tests/.

SIDECAR_OUTPUT="DELIGHT-SIDECAR"

# Native panel resolution, refresh and the scale that gives a usable desktop.
SIDECAR_PRESETS='{
  "ipad-11":        {"label":"iPad Pro 11\"",    "width":2388,"height":1668,"refresh":120,"scale":2},
  "ipad-13":        {"label":"iPad Pro 13\"",    "width":2752,"height":2064,"refresh":120,"scale":2},
  "ipad-air":       {"label":"iPad Air",         "width":2360,"height":1640,"refresh":60, "scale":2},
  "ipad-mini":      {"label":"iPad mini",        "width":2266,"height":1488,"refresh":60, "scale":2},
  "galaxy-tab-s9":  {"label":"Galaxy Tab S9",    "width":2560,"height":1600,"refresh":120,"scale":2},
  "pixel-tablet":   {"label":"Pixel Tablet",     "width":2560,"height":1600,"refresh":60, "scale":2},
  "android-1200p":  {"label":"Android tablet",   "width":1920,"height":1200,"refresh":60, "scale":1.5},
  "1080p":          {"label":"1080p tablet",     "width":1920,"height":1080,"refresh":60, "scale":1}
}'

SIDECAR_SIDES=(right left above below)

sidecar_presets_json() {
  jq -c 'to_entries | map({id: .key} + .value)' <<<"$SIDECAR_PRESETS"
}

# sidecar_mode <preset> <orientation> <custom-json>: resolved {label,width,height,refresh,scale}.
# preset "custom" reads width/height/refresh/scale from the custom object.
sidecar_mode() {
  local preset="$1" orientation="${2:-landscape}" custom="${3:-null}" mode
  if [[ $preset == "custom" ]]; then
    mode=$(jq -ce '{label: "Custom", width: (.width // empty), height: (.height // empty),
      refresh: (.refresh // 60), scale: (.scale // 1)}
      | select((.width | type) == "number" and (.height | type) == "number")' <<<"$custom") || return 1
  else
    mode=$(jq -ce --arg p "$preset" '.[$p] // empty' <<<"$SIDECAR_PRESETS") || return 1
  fi
  if [[ $orientation == "portrait" ]]; then
    jq -c '. + {width: .height, height: .width}' <<<"$mode"
  else
    printf '%s\n' "$mode"
  fi
}

sidecar_valid_side() {
  local side
  for side in "${SIDECAR_SIDES[@]}"; do
    [[ $1 == "$side" ]] && return 0
  done
  return 1
}

# sidecar_anchor <monitors-json>: the focused physical monitor (never the sidecar itself).
sidecar_anchor() {
  jq -r --arg out "$SIDECAR_OUTPUT" '
    [.[] | select(.name != $out)] as $m
    | (($m | map(select(.focused)) | first) // ($m | first) // empty) | .name' <<<"$1"
}

# sidecar_auto_position <side>: Hyprland's auto placement for that edge of the layout.
sidecar_auto_position() {
  case "$1" in
    left) echo auto-center-left ;;
    above) echo auto-center-up ;;
    below) echo auto-center-down ;;
    *) echo auto-center-right ;;
  esac
}

# sidecar_layout <monitors-json>: positions of every monitor except the tablet.
sidecar_layout() {
  jq -c --arg n "$SIDECAR_OUTPUT" '[.[] | select(.name != $n) | {name, x, y}] | sort_by(.name)' <<<"$1"
}

# sidecar_position <monitors-json> <anchor> <side> <mode-json>: "XxY" in layout
# (logical) coordinates, flush against the anchor and centred on the shared edge.
sidecar_position() {
  local monitors="$1" anchor="$2" side="$3" mode="$4"
  jq -re --arg a "$anchor" --arg side "$side" --argjson mode "$mode" '
    def round: (. + 0.5 | floor);
    (map(select(.name == $a)) | first) as $m
    | select($m != null)
    | ($m.scale // 1) as $ms
    | (if (($m.transform // 0) % 2) == 1 then [$m.height, $m.width] else [$m.width, $m.height] end) as $px
    | ($px[0] / $ms | round) as $aw | ($px[1] / $ms | round) as $ah
    | ($mode.width / $mode.scale | round) as $sw | ($mode.height / $mode.scale | round) as $sh
    | if $side == "right" then [$m.x + $aw, $m.y + (($ah - $sh) / 2 | round)]
      elif $side == "left" then [$m.x - $sw, $m.y + (($ah - $sh) / 2 | round)]
      elif $side == "above" then [$m.x + (($aw - $sw) / 2 | round), $m.y - $sh]
      elif $side == "below" then [$m.x + (($aw - $sw) / 2 | round), $m.y + $ah]
      else empty end
    | "\(.[0])x\(.[1])"' <<<"$monitors"
}

# Hyprland Lua keeps scales like 1.5 as numbers; integers print without a dot.
sidecar_num() {
  jq -r 'tostring' <<<"$1"
}

sidecar_mode_string() {
  jq -r '"\(.width)x\(.height)@\(.refresh)"' <<<"$1"
}

# sidecar_monitor_lua <mode-json> <position>: runtime rule for `hyprctl eval`
# and for the reload-safe file dofile'd by hypr.lua.
sidecar_monitor_lua() {
  local mode="$1" position="$2"
  printf 'hl.monitor({ output = "%s", mode = "%s", position = "%s", scale = %s })\n' \
    "$SIDECAR_OUTPUT" "$(sidecar_mode_string "$mode")" "$position" "$(sidecar_num "$(jq -c .scale <<<"$mode")")"
}

sidecar_lua_quote() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  printf '"%s"' "$s"
}

sidecar_dispatch_move_workspace() {
  printf 'hl.dsp.workspace.move({ workspace = %s, monitor = %s })\n' "$(sidecar_lua_quote "$1")" "$(sidecar_lua_quote "$2")"
}

sidecar_dispatch_focus_monitor() {
  printf 'hl.dsp.focus({ monitor = %s })\n' "$(sidecar_lua_quote "$1")"
}

# sidecar_sunshine_args <capture> <encoder>: key=value overrides, one per line.
# Sunshine applies argv key=value pairs on top of the user's sunshine.conf, so
# the user's file is never edited. wlr screencopy is the capture method that
# sees headless outputs (KMS only sees physical connectors).
sidecar_sunshine_args() {
  local capture="${1:-}" encoder="${2:-}"
  printf 'output_name=%s\n' "$SIDECAR_OUTPUT"
  [[ -z $capture ]] || printf 'capture=%s\n' "$capture"
  [[ -z $encoder ]] || printf 'encoder=%s\n' "$encoder"
  return 0
}

# sidecar_pin_payload <pending-json> <pin> <name>: body for POST /api/pin.
# New Sunshine lists pending requests (GET /api/pin -> {pairings:[{id,...}]})
# and needs the pairing_id; older builds take just {pin,name}.
sidecar_pin_payload() {
  local pending="$1" pin="$2" name="$3"
  jq -cn --argjson p "${pending:-null}" --arg pin "$pin" --arg name "$name" '
    (if ($p | type) == "object" then ($p.pairings // []) else [] end | last) as $req
    | if $req then {pairing_id: $req.id, pin: $pin, name: $name} else {pin: $pin, name: $name} end'
}

sidecar_valid_pin() {
  [[ $1 =~ ^[0-9]{4}$ ]]
}
