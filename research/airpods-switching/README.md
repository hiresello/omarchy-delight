# AirPods auto-switching and in-ear detection on Linux

Research only. Nothing here is wired into `install.sh` or any module.

## Recommendation: GO for a scoped "AirPods" module; NO-GO for Apple-parity auto-switching

Go: battery levels, in-ear detection (pause/resume media), noise-control mode,
"connect AirPods to this laptop" in one click, and making the AirPods the
default PipeWire sink when they connect. All of this works on Linux today via
open tools (`podctl`, LibrePods, MagicPods) on top of BlueZ + PipeWire.

No-go: Apple's automatic switching. Apple decides which device "owns" the
AirPods through iCloud-account coordination between Apple devices. A Linux
laptop is not part of that account mesh, so it cannot be offered the AirPods,
cannot tell the iPhone to give them up gracefully, and cannot reliably know
whether the buds are currently in use elsewhere. The best Linux can do is
*take* the AirPods on an explicit user action (or a narrowly defined trigger)
and switch audio locally. Ship that honestly labelled as "Connect", not "auto
switch".

## How it works

### BLE "Proximity Pairing" advertisements (no connection needed)

AirPods and the case broadcast Apple manufacturer data (company ID `0x004C`,
type `0x07`) documented in
[furiousMAC/continuity: proximity_pairing][cont-pp]: device model, a status
byte, left/right pod battery (nibbles, x10 %), charging flags and case battery,
lid-open counter, colour, and a 16-byte encrypted block. Any BLE scanner can
read the clear-text part; the encrypted part (more precise battery,
in-ear state) needs keys obtained once over the classic link (see below).
Advertisements are mostly sent while the buds are out of the case / the lid is
open and not connected, so they are good for "your AirPods are nearby, 80 %"
but not a reliable in-ear signal.

The spike [`spike/airpods-adv.sh`](spike/airpods-adv.sh) decodes one such
payload to JSON (raw status/charging bits are left undecoded because their
meaning is not verified):

```bash
research/airpods-switching/spike/airpods-adv.sh --self-test
research/airpods-switching/spike/airpods-adv.sh '07 19 01 0e 20 ...'
```

Feed it bytes from `bluetoothctl` (`scan on`, then `info <mac>` shows
`ManufacturerData.Key: 0x004c`) or `btmon`.

### Apple Accessory Protocol (AAP) over L2CAP (connected)

Once connected over classic Bluetooth, AirPods speak AAP on an L2CAP
SeqPacket socket, PSM `0x1001` ([podctl][podctl], [LibrePods][librepods]).
This gives: accurate battery per bud/case, **in-ear detection events**,
listening mode (off / noise cancellation / transparency / adaptive),
conversation awareness, head gestures on newer models, microphone selection,
and the identity-resolving key used to recognise the AirPods' rotating BLE
addresses later. podctl stores that key locally with restrictive permissions.

### Audio routing (BlueZ + PipeWire)

- Connecting: `bluetoothctl connect <mac>` (BlueZ D-Bus `org.bluez.Device1.Connect`).
- Sink selection: WirePlumber picks the configured default sink if present,
  otherwise the highest-priority available node. A module can set the
  AirPods as default with `wpctl set-default <id>` or `pactl set-default-sink`
  on connect, and restore the previous sink on disconnect.
- WirePlumber's built-in Bluetooth autoswitch only flips A2DP <-> HSP/HFP
  when an app records from the headset mic; it is not device handoff.
- In-ear pause/resume: on AAP ear-removal events call
  `playerctl pause` (MPRIS); resume on re-insertion if we paused it.

### Contention with Apple devices

- AirPods (H1/H2) hold one active audio link at a time towards Apple
  devices, with Apple-only "multipoint-like" switching. When the laptop calls
  `Connect` while an iPhone is playing, the AirPods usually accept the new
  host and the iPhone loses audio (stealing). Then the iPhone may
  automatically take them back when it starts playing again (ping-pong).
- LibrePods documents that some features (e.g. seamless multi-device
  behaviour) depend on spoofing an Apple `DeviceID` in
  `/etc/bluetooth/main.conf`; that is a system-wide BlueZ change and out of
  scope for a Delight module without a contract decision (verify per model).
- Therefore: never auto-connect when the AirPods may be in use elsewhere.
  Acceptable triggers: user clicks "Connect", or the case lid opens near the
  laptop *and* the laptop was the last host *and* the user opted in. Even then
  disable the trigger for a cool-down period after the iPhone takes them back.

## Existing Linux tools

| Tool | What it does | Notes |
| --- | --- | --- |
| [Rockykln/podctl][podctl] | Rust CLI + daemon: battery, in-ear, listening modes, conversation awareness, mic selection, BlueZ lifecycle, PipeWire/Pulse integration, JSON output. | Best fit to wrap from a Delight module. |
| [LibrePods][librepods] | AAP re-implementation (Android + Linux). Linux: auto connect, ear detection, battery, noise control. Multipoint listed as unsupported/unknown. | Alternative backend; Qt UI. |
| [steam3d/MagicPodsCore][magicpods] | Daemon with WebSocket API for AirPods (and some Beats/others): battery, ANC. | Good if a socket API is preferred. |
| `airpods-tui` | TUI for status. | Reference only. |
| [delphiki/AirStatus][airstatus] | Python BLE-advertisement battery reader. | Unmaintained since 2023; useful as a BLE parsing reference. |

## What works on Arch today

Verified on archlinux.org / aur.archlinux.org (2026-10).

| Package | Source | Purpose |
| --- | --- | --- |
| `bluez`, `bluez-utils` | repo (`extra`) | BlueZ daemon, `bluetoothctl`, `btmon` |
| `pipewire`, `pipewire-pulse`, `pipewire-audio`, `wireplumber` | repo (`extra`) | Audio graph, Bluetooth audio, sink selection (`wpctl`) |
| `libpulse` | repo (`extra`) | `pactl` |
| `playerctl` | repo (`extra`) | MPRIS pause/resume for in-ear detection |
| `dbus` | repo (`core`) | BlueZ D-Bus |
| `pulseaudio-bluetooth` | repo (`extra`) | Only for PulseAudio setups; Omarchy uses PipeWire, so not needed |
| `podctl-bin` / `podctl-git` | AUR (`0.3.0-1` / `0.3.0.r48.g568ce06-1`) | AAP backend |
| `librepods` / `librepods-rust-bin` | AUR (`1.0.0rc2-1` / `1-1`) | Alternative backend |
| `magicpods`, `magicpodscore` | AUR (`1.0.2-1`, `2.0.7-2`) | Alternative backend |
| `airpods-tui-bin` | AUR (`0.3.2-1`) | TUI |

Verification links: <https://archlinux.org/packages/extra/x86_64/bluez/>,
<https://archlinux.org/packages/extra/x86_64/wireplumber/>,
<https://aur.archlinux.org/packages/podctl-bin>,
<https://aur.archlinux.org/packages/librepods>,
<https://aur.archlinux.org/packages/magicpodscore>.

Omarchy already ships BlueZ and PipeWire/WirePlumber, so only the AAP backend
is new.

## Hardware requirements

- Any BlueZ-supported Bluetooth adapter with classic (BR/EDR) audio + BLE
  (practically all laptop combo cards). LE Audio is not required.
- AirPods with H1/H2 chips (AirPods 2/3/4, Pro 1/2, Max) for AAP features;
  1st-gen AirPods expose less (verify per model). Listening-mode and
  conversation-awareness support varies by model and firmware (verify).
- AirPods must be paired with the laptop once (hold the case button).

## Legal, ToS and privacy

- AAP is reverse-engineered; no Apple account or Apple service is involved,
  so Apple ToS exposure is low. Do not ship Apple trademarks/icons beyond
  nominative use ("works with AirPods"); use generic headphone icons.
- Spoofing an Apple `DeviceID` in BlueZ to unlock features misrepresents the
  host; keep it out of the default path.
- Privacy: BLE scanning sees *everyone's* nearby AirPods (model, battery,
  colour). Only surface devices paired with this laptop (match via the stored
  identity-resolving key / MAC); never log other people's advertisements.
- Identity-resolving keys and device MACs stay local with `0600` perms.
- Backends are third-party licences (check before packaging; verify).

## Prior art

- Continuity BLE notes: <https://github.com/furiousMAC/continuity>
- podctl: <https://github.com/Rockykln/podctl>
- LibrePods: <https://github.com/librepods-org/librepods>
- MagicPodsCore: <https://github.com/steam3d/MagicPodsCore>
- AirStatus: <https://github.com/delphiki/AirStatus>
- OpenPods (Android): <https://github.com/adolfintel/OpenPods>
- WirePlumber linking/default nodes: <https://pipewire.pages.freedesktop.org/wireplumber/policies/linking.html>
- Stute et al., Apple wireless ecosystem RE, USENIX Security 2019: <https://www.usenix.org/conference/usenixsecurity19/presentation/stute>

## Effort estimate

- Wrapper module over `podctl` (status, battery in `devices --json`, connect
  action, default-sink switch, in-ear pause/resume unit): 1 agent session
  (~2-3 human days).
- Plugin popover (battery rings, listening-mode toggle): +0.5 session.
- Lid-open auto-connect with cool-down: +0.5 session, experimental flag.
- Contract change first: `airpods` is not in the fixed module id list (or
  the work is folded into an existing module by its owner).

## Risks

- **Ping-pong with iPhone (high, UX).** Auto triggers will fight Apple's own
  switching. Mitigate: explicit action by default, cool-down, opt-in.
- **Backend maturity (medium).** All AAP tools are small, young AUR
  projects; protocol changes with AirPods firmware updates. Wrap behind a thin
  adapter so the backend can be swapped (podctl/LibrePods/MagicPods).
- **AUR dependency (medium).** `podctl-bin` has low adoption; `doctor` must
  report clearly if it is missing or broken.
- **Model variance (medium).** Features differ by model/firmware (verify).
- **Audio glitches (low).** Forcing default sink can surprise users with
  other headsets; remember and restore the previous default.

## `/goal` prompt for a future module

Prerequisite: a separate `contract-change` PR adding `airpods` to the fixed
module id list in `docs/contracts.md` and to `ci/ownership.json`.

```text
/goal Build the Delight module "airpods" in https://github.com/hiresello/omarchy-delight: AirPods battery, in-ear pause/resume, listening mode and one-click "Connect to this Mac-like laptop" on Omarchy, using BlueZ + PipeWire and the podctl backend.

Read docs/contracts.md first; it wins over this prompt. Read research/airpods-switching/README.md for background and constraints.

TRACK: id "airpods". Branch: track/airpods. Owned paths: modules/airpods/** only. Scaffold with `bin/delight dev new-module airpods`. Base on main, PR against main, iterate until CI (ci/local.sh) is green. If a shared file must change, open a SEPARATE PR labelled contract-change.

SCOPE
- modules/airpods/{module.json,defaults.json,bin/delight-airpods,systemd/,plugin/,tests/,README.md}.
- Verbs: install, uninstall, enable, disable, toggle, status [--json], doctor, pair, devices --json, open. Install/uninstall idempotent, recorded in ~/.local/state/omarchy-delight/airpods/installed.json; everything honors DELIGHT_DRY_RUN=1.
- Packages via pkg_add only: bluez, bluez-utils, wireplumber, playerctl (repo) and podctl-bin (AUR). Isolate podctl calls behind one backend function so LibrePods/MagicPods could replace it.
- devices --json: one entry per paired AirPods: {id, name, kind:"headphones", transport:"bluetooth", connected, mac}. Validate against schema/device.schema.json. Never list unpaired nearby AirPods.
- Status JSON via delight_status_write: on/off/busy/needs-setup ("Pair your AirPods in Bluetooth settings")/unsupported (no adapter, with reason). Subtitle "L 80% · R 75% · Case 40%" when connected. Actions: Connect/Disconnect, listening mode (off/ANC/transparency where supported), open plugin.
- Unit delight-airpods.service (PartOf=delight.target, WantedBy=delight.target): watches podctl events; on connect set AirPods as default sink with wpctl and remember the previous default; restore it on disconnect; on ear removal `playerctl pause` and resume only if we paused; rewrite status on every change.
- Contention: NEVER auto-connect by default. Optional defaults.json flag autoConnectOnLidOpen=false; when enabled, only connect if this laptop was the last host, and back off for 10 minutes after the AirPods are taken by another device.
- No changes to /etc/bluetooth/main.conf (no DeviceID spoofing).
- Plugin delight.airpods: battery per bud/case, listening-mode segmented control, Connect button; only qml/Delight components/tokens; generic headphone icons, no Apple artwork.
- Tests (TAP, tests/*-test.sh) with a stubbed podctl/wpctl/playerctl on PATH: devices JSON schema-valid, status in each state schema-valid, sink switch + restore, pause/resume bookkeeping, back-off timer, dry-run install/uninstall.

DO NOT TOUCH anything outside modules/airpods/**. No omarchy-* commands or omarchy.* ids. No logging of other people's BLE advertisements.
```

[cont-pp]: https://github.com/furiousMAC/continuity/blob/master/messages/proximity_pairing.md
[podctl]: https://github.com/Rockykln/podctl
[librepods]: https://github.com/librepods-org/librepods
[magicpods]: https://github.com/steam3d/MagicPodsCore
[airstatus]: https://github.com/delphiki/AirStatus
