#!/bin/bash

# Firewall rules, opened only to private LANs and tailscale0 (the same pattern
# as omarchy-install-service-sunshine). Every rule carries the comment
# "omarchy-delight:<id>".

delight_ufw_available() {
  delight_has_cmd ufw
}

delight_has_tailscale() {
  ip link show tailscale0 >/dev/null 2>&1
}

# delight_ufw_allow <id> <tcp|udp> <port|from:to>
delight_ufw_allow() {
  local id="$1" proto="$2" ports="$3" cidr tailscale=false
  if ! delight_ufw_available; then
    delight_log "$id: ufw is not installed; skipping firewall rule $proto $ports"
    return 0
  fi
  for cidr in "${DELIGHT_PRIVATE_CIDRS[@]}"; do
    delight_run_quiet sudo ufw allow in proto "$proto" from "$cidr" to any port "$ports" comment "omarchy-delight:$id"
  done
  if delight_has_tailscale; then
    tailscale=true
    delight_run_quiet sudo ufw allow in on tailscale0 to any port "$ports" proto "$proto" comment "omarchy-delight:$id"
  fi
  delight_state_add "$id" firewall "$(jq -cn --arg p "$proto" --arg r "$ports" --argjson t "$tailscale" '{proto:$p,ports:$r,tailscale:$t}')"
}

delight_ufw_revoke() {
  local id="$1" entry proto ports tailscale cidr
  while IFS= read -r entry; do
    [[ -n $entry ]] || continue
    proto=$(jq -r '.proto' <<<"$entry")
    ports=$(jq -r '.ports' <<<"$entry")
    tailscale=$(jq -r '.tailscale' <<<"$entry")
    if delight_ufw_available; then
      for cidr in "${DELIGHT_PRIVATE_CIDRS[@]}"; do
        delight_run_quiet sudo ufw delete allow in proto "$proto" from "$cidr" to any port "$ports" || true
      done
      if [[ $tailscale == "true" ]]; then
        delight_run_quiet sudo ufw delete allow in on tailscale0 to any port "$ports" proto "$proto" || true
      fi
    fi
    delight_state_del "$id" firewall "$entry"
  done < <(delight_state_list "$id" firewall)
}

delight_ufw_reload() {
  delight_ufw_available || return 0
  delight_run_quiet sudo ufw reload
}
