#!/bin/bash

hotspot_prox_params() {
  jq -cn \
    --argjson nearRssi "$(delight_config_get hotspot proximity.nearRssi)" \
    --argjson awayRssi "$(delight_config_get hotspot proximity.awayRssi)" \
    --argjson nearDwell "$(delight_config_get hotspot proximity.nearDwell)" \
    --argjson awayDwell "$(delight_config_get hotspot proximity.awayDwell)" \
    --argjson smoothing "$(delight_config_get hotspot proximity.smoothing)" \
    --argjson connectedIsNear "$(delight_config_get hotspot proximity.connectedIsNear)" \
    --argjson maxGap "$(delight_config_get hotspot proximity.maxGap)" \
    '{nearRssi:$nearRssi,awayRssi:$awayRssi,nearDwell:$nearDwell,awayDwell:$awayDwell,smoothing:$smoothing,connectedIsNear:$connectedIsNear,maxGap:$maxGap}'
}

hotspot_prox_step() {
  jq -cn --argjson now "$2" --arg rssi "$3" --argjson connected "$4" --argjson params "$5" \
    --argjson initial "$(if [[ -n $1 ]]; then printf '%s' "$1"; else printf '{}'; fi)" '
    ($connected == true or $connected == 1) as $is_connected
    | ({
      presence: "unknown",
      since: null,
      pending: null,
      pendingSince: null,
      smoothed: null,
      rssi: null,
      connected: false,
      lastAt: null,
      changed: false,
      from: null
    } + $initial) as $old
    | (if $old.pending != null and $old.lastAt != null and ($now - $old.lastAt) > $params.maxGap
       then ($old | .pendingSince = $now) else $old end) as $gap
    | (if $rssi != "" then ($rssi | tonumber)
       elif $is_connected and $params.connectedIsNear then $params.nearRssi else -127 end) as $value
    | (if $is_connected and $params.connectedIsNear and $rssi != ""
       then [$value,$params.nearRssi] | max else $value end) as $sample
    | (if $gap.smoothed == null then $sample
       else $params.smoothing * $sample + (1 - $params.smoothing) * $gap.smoothed end) as $smooth
    | (if $smooth >= $params.nearRssi then "near"
       elif $smooth < $params.awayRssi then "away" else "between" end) as $zone
    | (if $gap.presence == "near" then
         if $zone == "away" then
           (if $gap.pending == "away" then $gap.pendingSince else $now end) as $since
           | (if ($now - $since) >= $params.awayDwell then "away"
              else "near" end) as $new_presence
           | {presence:$new_presence,pending:(if $new_presence == "away" then null else "away" end),
              pendingSince:(if $new_presence == "away" then null else $since end)}
         else {presence:"near",pending:null,pendingSince:null} end
       elif $gap.presence == "away" then
         if $zone == "near" then
           (if $gap.pending == "near" then $gap.pendingSince else $now end) as $since
           | (if ($now - $since) >= $params.nearDwell then "near"
              else "away" end) as $new_presence
           | {presence:$new_presence,pending:(if $new_presence == "near" then null else "near" end),
              pendingSince:(if $new_presence == "near" then null else $since end)}
         else {presence:"away",pending:null,pendingSince:null} end
       else
         if $zone == "near" or $zone == "away" then
           (if $gap.pending == $zone then $gap.pendingSince else $now end) as $since
           | (if $zone == "near" then $params.nearDwell else $params.awayDwell end) as $dwell
           | if ($now - $since) >= $dwell then
               {presence:$zone,pending:null,pendingSince:null}
             else {presence:"unknown",pending:$zone,pendingSince:$since} end
         else {presence:"unknown",pending:null,pendingSince:null} end
       end) as $decision
    | ($decision.presence != $gap.presence) as $changed
    | $gap + $decision + {
        smoothed:$smooth,
        rssi:(if $rssi == "" then null else ($rssi | tonumber) end),
        connected:$is_connected,
        lastAt:$now,
        changed:$changed,
        from:(if $changed then $gap.presence else $gap.from end),
        since:(if $changed then $now else $gap.since end)
      }'
}
