#!/bin/bash

# shellcheck source=../../../tests/lib/tap.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../../../tests/lib/tap.sh"

sandbox
export PATH="$DELIGHT_TEST_REPO/modules/phone/tests/stubs:$PATH"
export DELIGHT_PHONE_FIXTURE="$DELIGHT_TEST_REPO/modules/phone/tests/fixtures/devices.json"

ROOT="$DELIGHT_TEST_REPO"
BIN="$ROOT/modules/phone/bin/delight-phone"
SCHEMA="$ROOT/schema"
mkdir -p "$HOME/.config"
printf '%s\n' "keep me" >"$HOME/.config/kdeconnect.notifyrc"
touch "$DELIGHT_STUB_STATE/pkg-kdeconnect"

devices_json() {
  "$BIN" devices --json
}

share_targets_json() {
  "$BIN" share-targets --json
}

devices=$(devices_json)
ok "paired devices validate against schema" schema_valid "$SCHEMA/device.schema.json" <(printf '%s\n' "$devices")
is "reachable Android device includes battery state" \
  "$(jq -c '.[] | select(.id == "pixel8") | [.name,.kind,.connected,.battery.charge,.battery.charging]' <<<"$devices")" \
  '["Pixel 8","phone",true,82,true]'
is "unreachable iPhone is marked limited" \
  "$(jq -c '.[] | select(.id == "iphone") | [.name,.connected,.limited]' <<<"$devices")" \
  '["iPhone",false,true]'
is "missing daemon produces empty device list" \
  "$(DELIGHT_PHONE_NO_DAEMON=true devices_json)" "[]"

targets=$(share_targets_json)
ok "share targets validate against schema" schema_valid "$SCHEMA/share-target.schema.json" <(printf '%s\n' "$targets")
is "only reachable share-enabled phone is exposed" \
  "$(jq -c 'map(.id)' <<<"$targets")" '["phone:pixel8"]'
printf '%s\n' "send me" >"$SANDBOX/shared file.txt"
ok "send shares an absolute file path" "$BIN" send phone:pixel8 "$SANDBOX/shared file.txt"
ok "share command has KDE Connect arguments" grep -F "kdeconnect-cli --share $SANDBOX/shared file.txt -d pixel8" "$DELIGHT_STUB_LOG"
not_ok "unknown share target fails" "$BIN" send phone:unknown "$SANDBOX/shared file.txt"
not_ok "missing file fails" "$BIN" send phone:pixel8 "$SANDBOX/missing.txt"

: >"$DELIGHT_STUB_LOG"
ok "ring uses the reachable paired device" "$BIN" ring
ok "ring command has KDE Connect arguments" grep -F "kdeconnect-cli --ring -d pixel8" "$DELIGHT_STUB_LOG"
not_ok "ring fails when no phone is reachable" env DELIGHT_PHONE_NO_REACHABLE=true "$BIN" ring

ok "module install prepares status and runtime" "$BIN" install
ok "module enable configures the daemon" "$BIN" enable
status=$("$BIN" status --json)
ok "enabled status validates against schema" schema_valid "$SCHEMA/status.schema.json" <(printf '%s\n' "$status")
is "enabled status is on" "$(jq -r '.state' <<<"$status")" "on"
ok "enabled subtitle names Pixel and charge" jq -e '.subtitle | contains("Pixel 8") and contains("82%")' <<<"$status"
ok "reachable status offers Ring" jq -e 'any(.actions[]; .label == "Ring")' <<<"$status"
starting=$(DELIGHT_PHONE_NO_DAEMON=true "$BIN" status --json)
is "enabled status remains on while daemon starts" "$(jq -r '.state' <<<"$starting")" "on"
ok "missing daemon status says Starting" jq -e '.subtitle | contains("Starting")' <<<"$starting"
not_ok "unreachable status omits Ring" jq -e 'any(.actions[]; .label == "Ring")' <<<"$starting"

pair=$("$BIN" pair --json)
ok "pairing JSON has expected shape" jq -e '
  .name == "Delight PC" and .id == "computer-id" and
  (.addresses | index("192.168.1.42") != null) and .discoverable[0].id == "newphone" and
  .requests[0].verificationKey == "PAIR-5678" and .qr != "" and .appUrl != ""
' <<<"$pair"
ok "pair accept calls acceptPairing" "$BIN" pair accept request1
ok "pairing request call is logged" grep -F "acceptPairing" "$DELIGHT_STUB_LOG"

signal='{"member":"notificationPosted","path":"/modules/kdeconnect/devices/pixel8/notifications/notif_1","data":["notif_1"]}'
ok "notificationPosted is handled" "$BIN" handle-signal "$signal"
ok "mirrored notification uses app, title, and body" grep -F 'omarchy-notification-send --app-name omarchy-delight-phone -g 󰄜 -p Messages New message: Hello there' "$DELIGHT_STUB_LOG"
map="$XDG_RUNTIME_DIR/omarchy-delight/phone/notifications.json"
ok "notification ID mapping is stored" jq -e '."pixel8/notif_1" == "77"' "$map"
removed='{"member":"notificationRemoved","path":"/modules/kdeconnect/devices/pixel8/notifications/notif_1","data":["notif_1"]}'
ok "notificationRemoved closes desktop notification" "$BIN" handle-signal "$removed"
ok "notification close method is logged" grep -F "CloseNotification u 77" "$DELIGHT_STUB_LOG"
ok "notification mapping is removed" jq -e 'has("pixel8/notif_1") | not' "$map"

ok "notificationPosted creates mapping for reverse dismissal" "$BIN" handle-signal "$signal"
closed='{"member":"NotificationClosed","data":[77,2]}'
ok "desktop dismissal asks phone to dismiss" "$BIN" handle-signal "$closed"
ok "phone dismiss method is logged" grep -F "/devices/pixel8/notifications/notif_1 org.kde.kdeconnect.device.notifications.notification dismiss" "$DELIGHT_STUB_LOG"
silent='{"member":"notificationPosted","path":"/modules/kdeconnect/devices/pixel8/notifications/notif_2","data":["notif_2"]}'
ok "silent notification is ignored" env DELIGHT_PHONE_SILENT=true "$BIN" handle-signal "$silent"
ok "silent notification is not mapped" jq -e 'has("pixel8/notif_2") | not' "$map"

sms=$("$BIN" sms list --json)
is "SMS list parses conversation message fields" \
  "$(jq -c 'map([.threadId,.addresses[0],.body,.read,.outgoing])' <<<"$sms")" \
  '[[42,"+15551234567","Reply from the computer",true,true],[42,"+15551234567","Hello from the phone",true,false]]'
ok "SMS reply succeeds" "$BIN" sms reply 42 "Reply from Delight"
ok "SMS reply uses conversations D-Bus signature" grep -F "replyToConversation xsav 42 Reply from Delight 0" "$DELIGHT_STUB_LOG"
message_signal='{"member":"conversationCreated","path":"/modules/kdeconnect/devices/pixel8","data":[{"type":"(isaxiiixxav)","data":[1,"Cached SMS", [{"type":"(s)","data":["+15551234567"]}],1728600002000,1,0,42,9,0,[]]}]}'
ok "conversationCreated updates SMS cache" "$BIN" handle-signal "$message_signal"
loaded_signal='{"member":"conversationLoaded","path":"/modules/kdeconnect/devices/pixel8","data":[42,3]}'
ok "conversationLoaded marks a thread ready" "$BIN" handle-signal "$loaded_signal"
ok "SMS thread reads the cached messages" jq -s -e 'any(.[]; .body == "Cached SMS")' "$XDG_RUNTIME_DIR/omarchy-delight/phone/sms/pixel8.jsonl"
thread=$("$BIN" sms thread 42 --json)
ok "SMS thread filters cache by thread ID" jq -e 'length == 1 and .[0].body == "Cached SMS"' <<<"$thread"
limited_output=$(DELIGHT_PHONE_NO_DAEMON=false "$BIN" sms list --json --device iphone 2>&1)
limited_rc=$?
is "limited device SMS reports exit code 3" "$limited_rc" "3"
ok "limited device explains Android requirement" grep -F "SMS needs the Android app" <<<"$limited_output"

ok "install succeeds with preinstalled kdeconnect" "$BIN" install
state_file="$HOME/.local/state/omarchy-delight/phone/installed.json"
is "preinstalled kdeconnect is not owned" \
  "$(jq -r '[.packages[].name] | index("kdeconnect") // "none"' "$state_file")" "none"
is "new packages are tracked" "$(jq -r '[.packages[].name] | index("qrencode") != null' "$state_file")" "true"
ok "pre-existing notifyrc is preserved" grep -Fx "keep me" "$HOME/.config/kdeconnect.notifyrc"
is "pre-existing notifyrc is not recorded" \
  "$(jq -r --arg path "$HOME/.config/kdeconnect.notifyrc" '[.files[] | select(. == $path)] | length' "$state_file")" "0"
ok "autostart and D-Bus overrides are installed" test -f "$HOME/.config/autostart/org.kde.kdeconnect.daemon.desktop" -a -f "$HOME/.local/share/dbus-1/services/org.kde.kdeconnect.service"
firewall_rules_present() {
  local proto cidr
  for proto in tcp udp; do
    for cidr in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
      grep -Fq "ufw allow in proto $proto from $cidr to any port 1714:1764 comment omarchy-delight:phone" "$DELIGHT_STUB_LOG" || return 1
    done
  done
}
ok "both firewall protocols are restricted to all three private subnets" firewall_rules_present
ok "unit files are installed" test -f "$HOME/.config/systemd/user/delight-phone.service" -a -f "$HOME/.config/systemd/user/delight-phone-bridge.service"
touch "$DELIGHT_STUB_STATE/pkg-qrencode"
ok "uninstall succeeds" "$BIN" uninstall
not_ok "uninstall removes module-owned D-Bus service file" test -e "$HOME/.local/share/dbus-1/services/org.kde.kdeconnect.service"
not_ok "uninstall removes module units" test -e "$HOME/.config/systemd/user/delight-phone.service" -o -e "$HOME/.config/systemd/user/delight-phone-bridge.service"
ok "uninstall preserves pre-existing notifyrc" grep -Fx "keep me" "$HOME/.config/kdeconnect.notifyrc"
not_ok "uninstall preserves preinstalled kdeconnect package" grep -F "pacman -Rns --noconfirm -- kdeconnect" "$DELIGHT_STUB_LOG"
ok "uninstall removes package recorded as module-owned" grep -F "pacman -Rns --noconfirm -- qrencode" "$DELIGHT_STUB_LOG"

before_hash=$(tree_hash "$HOME" "$XDG_RUNTIME_DIR")
ok "dry-run install exits successfully" env DELIGHT_DRY_RUN=1 "$BIN" install
is "dry-run install does not touch home or runtime" "$(tree_hash "$HOME" "$XDG_RUNTIME_DIR")" "$before_hash"

done_testing
