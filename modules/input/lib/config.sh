#!/bin/bash

# Pure generators for the input module's config files. Each function reads a
# settings JSON object on stdin and prints the file's text, so test goldens are
# byte-stable. Settings shape:
#   {"role":"share|receive","backend":"deskflow|lan-mouse","name":"<screen>",
#    "dir":"<deskflow config dir>","clipboard":true,
#    "peers":[{"name","host","edge":"left|right|top|bottom","fingerprint":""}]}

# Normalise a fingerprint (colon hex or plain hex) to lowercase colon form.
input_fp_colons() {
  local fp
  fp=$(tr -d ':' <<<"${1:-}" | tr 'A-F' 'a-f')
  [[ $fp =~ ^[0-9a-f]+$ ]] || return 1
  sed 's/../&:/g; s/:$//' <<<"$fp"
}

# Normalise a fingerprint to deskflow's `v2:sha256:<hex>` trusted-DB form.
input_fp_deskflow() {
  local fp
  fp=$(tr -d ':' <<<"${1:-}" | tr 'A-F' 'a-f')
  [[ $fp =~ ^[0-9a-f]+$ ]] || return 1
  printf 'v2:sha256:%s\n' "$fp"
}

input_peer_has_fingerprint() {
  jq -e '.fingerprint // "" | test("^[0-9A-Fa-f:]+$") and (gsub(":";"") | length > 0)' >/dev/null
}

# Deskflow's opposite edge for a peer edge (lan-mouse top/bottom = up/down).
input_edge_opposite() {
  case "$1" in
    left) echo right ;;
    right) echo left ;;
    top) echo down ;;
    bottom) echo up ;;
  esac
}

# Edge keyword deskflow uses in the links section.
input_edge_deskflow() {
  case "$1" in
    top) echo up ;;
    bottom) echo down ;;
    *) echo "$1" ;;
  esac
}

# Deskflow QSettings INI (deskflow/Deskflow.conf).
input_deskflow_ini() {
  local settings="$1" name role dir clipboard any_fp=false peer
  name=$(jq -r '.name' <<<"$settings")
  role=$(jq -r '.role' <<<"$settings")
  dir=$(jq -r '.dir // ""' <<<"$settings")
  clipboard=$(jq -r '.clipboard' <<<"$settings")
  while IFS= read -r peer; do
    [[ -n $peer ]] || continue
    if input_peer_has_fingerprint <<<"$peer"; then
      any_fp=true
      break
    fi
  done < <(jq -c '.peers[]?' <<<"$settings")

  if [[ $role == "share" ]]; then
    cat <<INI
[core]
coreMode=2
computerName=$name
port=24800
[server]
externalConfig=true
externalConfigFile=$dir/deskflow-server.conf
enableClipboard=$clipboard
[security]
tlsEnabled=true
checkPeerFingerprints=$any_fp
[log]
level=INFO
INI
  else
    cat <<INI
[core]
coreMode=1
computerName=$name
port=24800
[client]
remoteHost=$(jq -r '.peers[0].host // ""' <<<"$settings")
[security]
tlsEnabled=true
checkPeerFingerprints=$any_fp
[log]
level=INFO
INI
  fi
}

# Deskflow server screen/link config (share role only).
input_deskflow_server_conf() {
  local settings="$1" name peer edge
  name=$(jq -r '.name' <<<"$settings")

  echo "section: screens"
  printf '\t%s:\n' "$name"
  while IFS= read -r peer; do
    [[ -n $peer ]] || continue
    printf '\t%s:\n' "$(jq -r '.name' <<<"$peer")"
  done < <(jq -c '.peers[]?' <<<"$settings")
  echo "end"

  echo "section: links"
  printf '\t%s:\n' "$name"
  while IFS= read -r peer; do
    [[ -n $peer ]] || continue
    edge=$(input_edge_deskflow "$(jq -r '.edge' <<<"$peer")")
    printf '\t\t%s = %s\n' "$edge" "$(jq -r '.name' <<<"$peer")"
  done < <(jq -c '.peers[]?' <<<"$settings")
  while IFS= read -r peer; do
    [[ -n $peer ]] || continue
    edge=$(input_edge_deskflow "$(input_edge_opposite "$(jq -r '.edge' <<<"$peer")")")
    printf '\t%s:\n' "$(jq -r '.name' <<<"$peer")"
    printf '\t\t%s = %s\n' "$edge" "$name"
  done < <(jq -c '.peers[]?' <<<"$settings")
  echo "end"

  echo "section: options"
  printf '\tclipboardSharing = %s\n' "$(jq -r '.clipboard' <<<"$settings")"
  echo "end"
}

# Deskflow trusted fingerprint DB (trusted-clients for share, trusted-servers
# for receive): one `v2:sha256:<hex>` line per peer that has a fingerprint.
input_deskflow_trusted() {
  local settings="$1" peer fp
  while IFS= read -r peer; do
    [[ -n $peer ]] || continue
    if input_peer_has_fingerprint <<<"$peer"; then
      fp=$(input_fp_deskflow "$(jq -r '.fingerprint' <<<"$peer")")
      printf '%s\n' "$fp"
    fi
  done < <(jq -c '.peers[]?' <<<"$settings")
}

# Lan Mouse config.toml.
input_lan_mouse_toml() {
  local settings="$1" role peer fp
  role=$(jq -r '.role' <<<"$settings")

  cat <<'TOML'
port = 4242
release_bind = ["KeyLeftCtrl", "KeyLeftShift", "KeyLeftMeta", "KeyLeftAlt"]
capture_backend = "layer-shell"
emulation_backend = "wlroots"
TOML

  echo
  echo "[authorized_fingerprints]"
  while IFS= read -r peer; do
    [[ -n $peer ]] || continue
    if input_peer_has_fingerprint <<<"$peer"; then
      fp=$(input_fp_colons "$(jq -r '.fingerprint' <<<"$peer")")
      printf '"%s" = "%s"\n' "$fp" "$(jq -r '.name' <<<"$peer")"
    fi
  done < <(jq -c '.peers[]?' <<<"$settings")

  while IFS= read -r peer; do
    [[ -n $peer ]] || continue
    echo
    echo "[[clients]]"
    printf 'position = "%s"\n' "$(jq -r '.edge' <<<"$peer")"
    printf 'hostname = "%s"\n' "$(jq -r '.host' <<<"$peer")"
    echo "port = 4242"
    if [[ $role == "share" ]]; then
      echo "activate_on_startup = true"
    else
      echo "activate_on_startup = false"
    fi
  done < <(jq -c '.peers[]?' <<<"$settings")
}
