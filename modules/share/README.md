# share

AirDrop-style sharing for Omarchy over [LocalSend](https://localsend.org), plus
an optional Apple AirDrop mode on capable Wi-Fi adapters.

## What you get

- `SUPER + SHIFT + CTRL + S` — share sheet overlay (SUPER+S, SUPER+SHIFT+S and
  SUPER+CTRL+S are already taken by Omarchy's Share menu; SUPER+ALT+S is the
  scratchpad). Check conflicts with `omarchy menu keybindings --print`.
- Delight menu → **Share…** and a Control Center tile.
- Nautilus → right-click → **Share…** (`delight-share.py` in
  `~/.local/share/nautilus-python/extensions/`; lives next to Omarchy's
  `localsend.py` without touching it).
- Notifications when files arrive in LocalSend — clicking reveals the file in
  Files (`nautilus --select`).
- Optional AirDrop mode (`--airdrop`) for Apple devices.

## Verbs

| Verb | What it does |
|---|---|
| `sheet [paths...]` / `sheet --clipboard` | Open the share sheet. With no paths it asks `omarchy-file-select --multiple`. `--clipboard` pastes `wl-paste` into a temp file under `$XDG_RUNTIME_DIR/omarchy-delight/share/`. |
| `share-targets --json` | Discovered devices, per `schema/share-target.schema.json`. Never fails — prints `[]` on any error. `DELIGHT_SHARE_PEERS_FIXTURE=<file>` injects peers for tests. |
| `send <target-id> <paths...>` | `localsend:<fingerprint-or-ip>` or `airdrop:<name>`. Unknown prefix exits 64. Directories are refused with a clear message. |
| `enable --airdrop` | Adds the AUR packages `opendrop` + `owlink-git` and sets `airdrop=true`. Exits 2 when no monitor-mode adapter exists. |
| `disable --airdrop` | Sets `airdrop=false` (packages stay until `uninstall`). |
| `doctor [--airdrop]` | 0 ok · 1 fixable (missing localsend, ufw missing 53317, units missing) · 2 unsupported (AirDrop without monitor-mode Wi-Fi). |

## Discovery

LocalSend normally finds peers over UDP multicast (224.0.0.167:53317). We do
**not** use multicast: the LocalSend app on this machine already binds the
port, and bash cannot receive multicast cleanly. Instead `discover` does HTTP
legacy discovery per protocol §3.2 — it enumerates the /24 of every
non-loopback UP IPv4 interface (`ip -j -4 addr`) and `POST`s
`/api/localsend/v2/register` to every host in parallel (`xargs -P 64`, curl
`--max-time` from `discoveryTimeout`, https first then http), with
`/api/localsend/v2/info` as a fallback. Results are cached for 30s in
`$XDG_RUNTIME_DIR/omarchy-delight/share/peers.json` and feed both
`share-targets` and the tile subtitle.

## Send fallback

Omarchy wraps LocalSend as `localsend --headless send --to <ip>` but upstream
ships `localsend-cli` instead, so flags are detected at runtime: if
`localsend --headless send --help` (or `localsend-cli send --help`) mentions
`--to`, `send` uses it with `--to <ip>`; otherwise it speaks the protocol
directly with curl — `POST /api/localsend/v2/prepare-upload` then
`POST /api/localsend/v2/upload?sessionId&fileId&token` per file (204 = nothing
to send, 403 = rejected, 409 = busy).

## Receive notifications

`delight-share-receive.service` runs `watch-receive`: it makes sure LocalSend
is running (`setsid localsend --hidden` when it is not), then watches the
shared-preferences JSON for changes via `inotifywait`. For each new
`flutter.ls_receive_history` entry it sends a notification; file entries offer
"Reveal in Files" (click → `nautilus --select <path>`), message entries show
their text. Honours `notifyReceive=false`. Limits: the LocalSend app must be
the thing that actually receives (it owns port 53317); Delight only watches
its history file.

Preferences file: `~/.local/share/org.localsend.localsend_app/shared_preferences.json`
(APPLICATION_ID `org.localsend.localsend_app` in `app/linux/CMakeLists.txt`;
key `flutter.ls_receive_history` in `persistence_provider.dart`). Portable
mode's `settings.json` next to the `localsend` executable is used when present.

## AirDrop mode

`delight share enable --airdrop` requires a Wi-Fi adapter with monitor mode
and frame injection (`delight_hw_wifi_monitor` checks `iw list`), and installs
`opendrop` + `owlink-git` from the AUR — `opendrop` is seemoo-lab's open
AirDrop implementation and `owlink-git` builds `owl`, the AWDL userspace
daemon (`sudo owl -i <iface>`). Apple devices must set AirDrop to "Everyone".
AirDrop peers come from `opendrop find` (best-effort, timeout-guarded);
sending is `opendrop send -r <id> -f <file>`.

### "omdrop"

Research found that "omdrop" refers to a real ecosystem: `omdrop` is AirDrop
for Omarchy — `brentkearney/omdrop-plugin` (an Omarchy shell plugin targeting
Apple-Silicon Macs on Asahi with Broadcom Wi-Fi) and `t4t5/omdrop-owl`, the
radio backend that runs AWDL in userspace through OWL on monitor-capable
adapters (first target MediaTek MT7925). Delight's AirDrop mode uses the same
underlying building blocks (opendrop + OWL via `owlink-git`) rather than the
omdrop plugin itself; if omdrop matures it could become a provider here.

## VM acceptance steps

1. `delight share install` — localsend/jq/curl/inotify-tools present (localsend
   is preinstalled on Omarchy), `delight-share-receive.service` enabled,
   plugin `delight.share` visible in `omarchy plugin list`.
2. `delight share status` — state `on`, subtitle `LocalSend · N nearby`.
3. `SUPER+SHIFT+CTRL+S` — sheet opens, dims, Esc closes.
4. Right-click a file in Files → **Share…** — sheet opens with that file.
5. `delight share doctor` — `ok` (or explains what's missing).
6. `delight share toggle` twice — status goes off/on, unit stops/starts.
7. `delight share uninstall` — `delight-share.py` gone, `localsend.py` intact.

## [HW] manual test — real phones

1. Install LocalSend on an iPhone and an Android phone; join the same Wi-Fi.
2. On this machine: `delight share install && delight share enable`.
3. Run `delight share share-targets --json`. Expected: both phones appear
   with `"kind": "phone"`.
4. Press `SUPER+SHIFT+CTRL+S`, pick a file. Expected: both phones listed as
   targets within ~2s.
5. Select the iPhone. Expected: iPhone shows the incoming transfer; accepting
   receives the file; a "Sent" notification appears here.
6. From Android, send a photo to this machine (LocalSend must be running;
   the watcher starts it hidden if needed). Expected: a "Received <name>"
   notification; clicking it reveals the file in Files.
7. Text the machine from the phone. Expected: "Message from <alias>".
8. `delight share enable --airdrop` on unsupported hardware. Expected: exit
   2 with a monitor-mode explanation, `airdrop` stays false.
