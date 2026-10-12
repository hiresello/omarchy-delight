#!/bin/bash

# sync module: REST client against recorded Syncthing 2.1 fixtures, status
# mapping, notifications and the install/enable/toggle/uninstall lifecycle.

# shellcheck source=../../../tests/lib/tap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"

HERE="$DELIGHT_TEST_REPO/modules/sync/tests"
BIN="$DELIGHT_TEST_REPO/modules/sync/bin/delight-sync"
ME=UOR3FHY-HJFYMEI-5U5AXOD-Q4RHYXY-ZL5KSNZ-L76C6M6-BXGCIIS-IZ7ZGAP
PEER=JV2N5IJ-MIWTMJB-P6C2FY4-K5F2IL3-WPSDB6C-M7AYNID-EFYISGE-36JBHQC

sandbox
export PATH="$HERE/stubs:$PATH" FAKE_ST="$SANDBOX/fake-st" FAKE_ST_KEY=test-key
unset WAYLAND_DISPLAY STCONFDIR STHOMEDIR XDG_CONFIG_HOME XDG_STATE_HOME
mkdir -p "$FAKE_ST/routes" "$HOME/.local/state/syncthing"
printf '<configuration>\n  <gui enabled="true">\n    <address>127.0.0.1:8384</address>\n    <apikey>%s</apikey>\n  </gui>\n</configuration>\n' \
  "$FAKE_ST_KEY" >"$HOME/.local/state/syncthing/config.xml"

# route METHOD PATH [FIXTURE|-] — serve a fixture (or stdin) for a request.
route() {
  local file="$FAKE_ST/routes/$1${2//\//_}.json"
  if [[ ${3:--} == - ]]; then cat >"$file"; else sed "s:/home/u:$HOME:g" "$HERE/fixtures/$3.json" >"$file"; fi
}
requests() { cat "$FAKE_ST/requests.log" 2>/dev/null; }
reset_requests() { : >"$FAKE_ST/requests.log"; }

base_routes() {
  rm -f "$FAKE_ST/routes"/*
  echo '{"status":"OK"}' | route GET /rest/noauth/health
  route GET /rest/system/status system-status
  route GET /rest/config "${1:-config-paired}"
  jq '.folders' "$FAKE_ST/routes/GET_rest_config.json" | route GET /rest/config/folders
  jq '.devices' "$FAKE_ST/routes/GET_rest_config.json" | route GET /rest/config/devices
  jq '.gui' "$FAKE_ST/routes/GET_rest_config.json" | route GET /rest/config/gui
  jq '.folders[0] // {}' "$FAKE_ST/routes/GET_rest_config.json" | route GET /rest/config/folders/default
  route GET /rest/system/connections connections
  echo '{}' | route GET /rest/cluster/pending/devices
  route GET /rest/db/completion completion
  route GET /rest/db/status@default "${2:-db-status-idle}"
  echo '[]' | route GET /rest/events
}
snapshot_fields() {
  (
    # shellcheck source=../lib/syncthing.sh
    source "$DELIGHT_TEST_REPO/modules/sync/lib/syncthing.sh"
    sync_snapshot | sync_status_fields
  )
}
subtitle() { snapshot_fields | jq -r "${1:-.subtitle}"; }

# shellcheck source=../lib/syncthing.sh
source "$DELIGHT_TEST_REPO/modules/sync/lib/syncthing.sh"

echo "# REST client"
base_routes
is "API key is read from the 2.x state dir" "$(sync_api_key)" "$FAKE_ST_KEY"
mkdir -p "$HOME/.config/syncthing"
sed 's/test-key/legacy-key/' "$HOME/.local/state/syncthing/config.xml" >"$HOME/.config/syncthing/config.xml"
is "a legacy ~/.config/syncthing config wins" "$(sync_api_key)" "legacy-key"
rm -rf "$HOME/.config/syncthing"
is "device IDs are normalised" "$(sync_normalize_id "${PEER,,}")" "$PEER"
is "device IDs without dashes are accepted" "$(sync_normalize_id "${PEER//-/}")" "$PEER"
not_ok "garbage device IDs are rejected" sync_normalize_id "not-a-device"
is "GET returns the body" "$(sync_my_id)" "$ME"
is "requests go to the loopback API" "$(sync_api_base)" "http://127.0.0.1:8384"
not_ok "a wrong API key fails (HTTP 403)" env SYNC_API_KEY=wrong bash -c "source '$DELIGHT_TEST_REPO/modules/sync/lib/syncthing.sh'; sync_api GET /rest/config"
not_ok "a missing endpoint fails" sync_api GET /rest/nope
ok "health check passes while up" sync_api_up
touch "$FAKE_ST/down"
not_ok "health check fails while down" sync_api_up
rm "$FAKE_ST/down"
is "devices are resolved by name" "$(sync_resolve_device PHONE-B)" "$PEER"

reset_requests
mkdir -p "$SANDBOX/photos"
id=$(sync_add_folder "$SANDBOX/photos" "" "")
ok "add-folder POSTs a sendreceive folder for the path" grep -q "^POST /rest/config/folders .*\"path\":\"$SANDBOX/photos\".*\"type\":\"sendreceive\"" <(requests)
ok "add-folder generates an id from the label" grep -Eq '^photos-[a-z0-9]{5}$' <<<"$id"
is "add-folder reuses an existing folder for the same path" "$(sync_add_folder "$HOME/Sync")" "default"

reset_requests
sync_share_folder default "$ME" >/dev/null
ok "sharing PATCHes the folder's device list" grep -q "^PATCH /rest/config/folders/default .*\"$ME\"" <(requests)
reset_requests
sync_add_device "${PEER,,}" "pixel" >/dev/null
ok "add-device POSTs the canonical ID with dynamic addresses" \
  grep -q "^POST /rest/config/devices {\"deviceID\":\"$PEER\",\"name\":\"pixel\",\"addresses\":\[\"dynamic\"\]}" <(requests)
reset_requests
sync_ignore_device "$PEER" >/dev/null
ok "ignore PUTs remoteIgnoredDevices" grep -q "^PUT /rest/config .*remoteIgnoredDevices.*$PEER" <(requests)
ok "ignore clears the pending entry" grep -q "^DELETE /rest/cluster/pending/devices?device=$PEER" <(requests)

echo "# status mapping"
base_routes
is "idle and connected is up to date" "$(subtitle)" "Up to date"
is "up to date is on" "$(subtitle .state)" "on"
base_routes config-paired db-status-syncing
is "syncing shows a percentage" "$(subtitle)" "Syncing 85%"
is "syncing is busy" "$(subtitle .state)" "busy"
base_routes config-paused
is "paused devices show as paused" "$(subtitle)" "Paused"
is "paused is off" "$(subtitle .state)" "off"
base_routes
jq '.connections[].connected = false' "$HERE/fixtures/connections.json" | route GET /rest/system/connections
is "a disconnected peer is named" "$(subtitle)" "phone-b disconnected"
base_routes config-empty
route GET /rest/cluster/pending/devices pending-devices
is "pending requests are counted" "$(subtitle)" "1 device wants to pair"
base_routes config-empty
echo '{}' | route GET /rest/system/connections
is "no peers means ready to pair" "$(subtitle)" "Ready to pair"
base_routes
mkdir -p "$HOME/Sync/.stversions"
touch "$HOME/Sync/a.sync-conflict-20261012-091525-JV2N5IJ.txt" "$HOME/Sync/b.sync-conflict-20261012-091526-JV2N5IJ.txt"
touch "$HOME/Sync/.stversions/c.sync-conflict-20261012-091527-JV2N5IJ.txt" "$HOME/Sync/notes.sync-conflict-draft.txt"
is "conflict files are counted (versions and look-alikes ignored)" "$(subtitle)" "2 conflicts"
is "the conflicted folder is reported" "$(subtitle .conflictFolder)" "$HOME/Sync"
rm -rf "$HOME/Sync"
base_routes
jq '.state = "error"' "$HERE/fixtures/db-status-idle.json" | route GET /rest/db/status@default
is "folder errors are an error state" "$(subtitle .state)" "error"
ok "folder errors carry a reason" test -n "$(subtitle '.reason // empty')"
base_routes
is "devices list the peer only" "$(sync_snapshot | sync_devices_from | jq -c '[.[] | {id, name, kind, connected}]')" \
  "[{\"id\":\"$PEER\",\"name\":\"phone-b\",\"kind\":\"phone\",\"connected\":true}]"

echo "# module lifecycle"
base_routes
touch "$DELIGHT_STUB_STATE/pkg-qrencode"
not_ok "devices --json needs the flag" "$BIN" devices
before=$(tree_hash "$HOME")
DELIGHT_DRY_RUN=1 "$BIN" install >/dev/null 2>&1
is "dry-run install changes nothing" "$(tree_hash "$HOME")" "$before"
ok "install succeeds" "$BIN" install
dropin="$HOME/.config/systemd/user/syncthing.service.d/delight-sync.conf"
ok "install adds the syncthing.service drop-in" grep -q '^PartOf=delight.target' "$dropin"
ok "the drop-in pins the GUI/API to loopback" grep -q '^Environment=STGUIADDRESS=127.0.0.1:8384' "$dropin"
ok "install adds delight-sync.service" test -f "$HOME/.config/systemd/user/delight-sync.service"
ok "install installs syncthing" grep -q '^omarchy-pkg-add .*syncthing' "$DELIGHT_STUB_LOG"
for rule in "tcp.*port 22000" "udp.*port 22000" "udp.*port 21027"; do
  ok "ufw allows $rule from private ranges" grep -Eq "^ufw allow in proto ${rule%%.*} from 192\.168\.0\.0/16 to any port ${rule##* } comment omarchy-delight:sync" "$DELIGHT_STUB_LOG"
done
not_ok "no ufw rule is open to any source" grep -Eq '^ufw allow .*from (any|0\.0\.0\.0)' "$DELIGHT_STUB_LOG"
ok "install is idempotent" "$BIN" install
is "status after install is off" "$("$BIN" status --json | jq -r .state)" "off"

touch "$DELIGHT_STUB_STATE/pkg-syncthing"
echo '[]' | route GET /rest/config/folders
reset_requests
: >"$DELIGHT_STUB_LOG"
ok "enable succeeds" "$BIN" enable
ok "enable starts syncthing.service" grep -q '^systemctl --user enable --now syncthing.service' "$DELIGHT_STUB_LOG"
ok "enable starts the status watcher" grep -q '^systemctl --user enable --now delight-sync.service' "$DELIGHT_STUB_LOG"
ok "enable creates the default ~/Sync folder over REST" grep -q "^POST /rest/config/folders {\"id\":\"default\",\"label\":\"Sync\",\"path\":\"$HOME/Sync\"" <(requests)
ok "the default folder exists on disk" test -d "$HOME/Sync"
not_ok "a loopback GUI address is left alone" grep -q '^PATCH /rest/config/gui' <(requests)
ok "enable resumes sync" grep -q '^POST /rest/system/resume' <(requests)
reset_requests
jq '.address = "0.0.0.0:8384"' "$FAKE_ST/routes/GET_rest_config_gui.json" | route GET /rest/config/gui
"$BIN" enable >/dev/null 2>&1
ok "a non-loopback GUI address is moved back to 127.0.0.1" grep -q '^PATCH /rest/config/gui {"address":"127.0.0.1:8384"}' <(requests)
not_ok "the default folder is only created on first enable" grep -q '^POST /rest/config/folders' <(requests)
base_routes

json=$("$BIN" status --json)
ok "status --json is schema-valid" schema_valid "$DELIGHT_TEST_REPO/schema/status.schema.json" <(echo "$json")
is "status reports up to date" "$(jq -r '.state + " " + .subtitle' <<<"$json")" "on Up to date"
is "status lists the peer" "$(jq -r '.devices[0].name' <<<"$json")" "phone-b"
ok "status offers pairing" jq -e '.actions | any(.command == ["delight","sync","pair"])' <<<"$json"
ok "devices --json is schema-valid" schema_valid "$DELIGHT_TEST_REPO/schema/device.schema.json" <("$BIN" devices --json)
touch "$FAKE_ST/down"
json=$("$BIN" status --json)
is "status --json still exits 0 while Syncthing is down" "$?" "0"
ok "status while down is schema-valid" schema_valid "$DELIGHT_TEST_REPO/schema/status.schema.json" <(echo "$json")
not_ok "pair fails clearly while Syncthing is down" "$BIN" pair --json
"$BIN" toggle >/dev/null 2>&1
is "toggle disables when Syncthing is unreachable" "$(jq -r '.modules.sync.enabled' "$HOME/.config/omarchy-delight/config.json")" "false"
rm "$FAKE_ST/down"
"$BIN" enable >/dev/null 2>&1

reset_requests
"$BIN" toggle >/dev/null 2>&1
ok "toggle pauses everything" grep -q '^POST /rest/system/pause' <(requests)
is "toggle keeps the module enabled" "$(jq -r '.modules.sync.enabled' "$HOME/.config/omarchy-delight/config.json" 2>/dev/null)" "true"
base_routes config-paused
reset_requests
"$BIN" toggle >/dev/null 2>&1
ok "toggle resumes when paused" grep -q '^POST /rest/system/resume' <(requests)
is "paused status is off" "$("$BIN" status --json | jq -r .subtitle)" "Paused"
base_routes

pair=$("$BIN" pair --json)
is "pair --json has this device ID" "$(jq -r .deviceId <<<"$pair")" "$ME"
ok "pair renders the ID as a QR image" grep -q "^QR $ME" "$(jq -r .qr <<<"$pair")"
ok "pair --terminal prints the QR" grep -q "^QR $ME" <("$BIN" pair --terminal)
route GET /rest/cluster/pending/devices pending-devices
is "pair --json lists pending requests" "$("$BIN" pair --json | jq -r '.pending[0].id + " " + .pending[0].name')" "$PEER 422465fd87ff"
reset_requests
ok "accept adds the device" "$BIN" accept "$PEER"
ok "accept uses the pending name" grep -q "^POST /rest/config/devices .*\"name\":\"422465fd87ff\"" <(requests)
ok "accept shares the default folder" grep -q "^PATCH /rest/config/folders/default .*$PEER" <(requests)
not_ok "accept rejects a bad ID" "$BIN" accept nope
reset_requests
ok "add-folder --share-with shares by device name" "$BIN" add-folder "$SANDBOX/docs" --share-with phone-b
ok "add-folder created the folder" grep -q "^POST /rest/config/folders .*\"path\":\"$SANDBOX/docs\"" <(requests)
ok "add-folder shared it with the device" grep -q "^POST /rest/config/folders .*\"devices\":\[{\"deviceID\":\"$PEER\"}\]" <(requests)
not_ok "add-folder rejects an unknown device" "$BIN" add-folder "$SANDBOX/x" --share-with nobody
reset_requests
is "add-folder ~/Sync maps to the default folder" "$("$BIN" add-folder "$HOME/Sync" --share-with "$PEER" 2>/dev/null)" "default"
ok "add-folder shares an existing folder" grep -q "^PATCH /rest/config/folders/default .*$PEER" <(requests)

echo "# watcher notifications"
: >"$DELIGHT_STUB_LOG"
route GET /rest/events events-pending
SYNC_WATCH_ONCE=1 timeout 20 "$BIN" watch >/dev/null 2>&1
is "one notification per new device (events repeat)" "$(grep -c '^omarchy-notification-send .*New device wants to sync' "$DELIGHT_STUB_LOG")" "1"
ok "the device notification opens pairing" grep -q 'New device wants to sync.*--exec delight sync pair' "$DELIGHT_STUB_LOG"
ok "the watcher writes status" test -s "$XDG_RUNTIME_DIR/omarchy-delight/status/sync.json"
: >"$DELIGHT_STUB_LOG"
route GET /rest/events events-conflict
SYNC_WATCH_ONCE=1 timeout 20 "$BIN" watch >/dev/null 2>&1
ok "conflicts notify" grep -q '^omarchy-notification-send .*Sync conflict' "$DELIGHT_STUB_LOG"
ok "the conflict notification opens the folder" grep -q "Sync conflict.*--exec xdg-open $HOME/Sync" "$DELIGHT_STUB_LOG"
base_routes

echo "# uninstall"
echo keep >"$HOME/Sync/photo.jpg"
data=$(tree_hash "$HOME/Sync" "$HOME/.local/state/syncthing")
: >"$DELIGHT_STUB_LOG"
ok "uninstall succeeds" "$BIN" uninstall
not_ok "uninstall removes the drop-in" test -e "$dropin"
not_ok "uninstall removes delight-sync.service" test -e "$HOME/.config/systemd/user/delight-sync.service"
ok "uninstall revokes the ufw rules" grep -q '^ufw delete' "$DELIGHT_STUB_LOG"
ok "uninstall stops syncthing.service it started" grep -q '^systemctl --user disable --now syncthing.service' "$DELIGHT_STUB_LOG"
ok "uninstall removes syncthing (Delight installed it)" grep -q '^sudo pacman -Rns --noconfirm -- syncthing' "$DELIGHT_STUB_LOG"
is "uninstall keeps ~/Sync and Syncthing's data" "$(tree_hash "$HOME/Sync" "$HOME/.local/state/syncthing")" "$data"
ok "uninstall is idempotent" "$BIN" uninstall

echo "# pre-existing syncthing"
touch "$DELIGHT_STUB_STATE/unit-syncthing.service"
: >"$DELIGHT_STUB_LOG"
"$BIN" install >/dev/null 2>&1
not_ok "a pre-installed syncthing is not reinstalled" grep -q '^omarchy-pkg-add' "$DELIGHT_STUB_LOG"
"$BIN" enable >/dev/null 2>&1
"$BIN" uninstall >/dev/null 2>&1
not_ok "a pre-enabled syncthing.service keeps running" grep -q '^systemctl --user disable --now syncthing.service' "$DELIGHT_STUB_LOG"
not_ok "a pre-installed syncthing is kept" grep -q 'pacman -Rns' "$DELIGHT_STUB_LOG"

done_testing
