# Sidecar

Use an iPad or Android tablet as a second display. `delight sidecar start` adds a
virtual Hyprland output, `DELIGHT-SIDECAR`, next to the monitor you are working
on and streams it with [Sunshine](https://github.com/LizardByte/Sunshine) to
[Moonlight](https://moonlight-stream.org) on the tablet, touch and keyboard
input included. Deskreen is an optional, view-only fallback.

## Quick start

```bash
delight sidecar install          # Sunshine, qrencode, unit, panel
delight sidecar start            # or click the Sidecar tile in the Control Center
delight sidecar open             # pairing + arrangement panel
delight sidecar stop
```

| Verb | What it does |
| --- | --- |
| `install [--deskreen]` / `uninstall` | Idempotent. Records only what Delight added. |
| `start` / `stop` (`enable` / `disable`, `toggle`) | Add / remove the tablet display. |
| `open` / `pair` | Summon the `delight.sidecar` panel. |
| `pair <PIN> [name]` | Accept the Moonlight pairing request via Sunshine's API. |
| `pair --pending` | Pending pairing requests (JSON). |
| `credentials <user>` | Store the Sunshine web UI login (password on stdin, saved 0600). |
| `set preset <id>` | `ipad-11` (default), `ipad-13`, `ipad-air`, `ipad-mini`, `galaxy-tab-s9`, `pixel-tablet`, `android-1200p`, `1080p`, `custom`. |
| `set orientation landscape\|portrait` | Portrait swaps the preset's width and height. |
| `set arrangement left\|right\|above\|below` | Applied live while running. |
| `set backend sunshine\|deskreen` | Deskreen is view-only. |
| `set hotkey "<keys>"` | Optional toggle binding, e.g. `"SUPER + CTRL + ALT + T"`; `""` removes it. |
| `presets`, `info --json` | Data for the panel. |
| `doctor` | Hyprland headless support, Sunshine, credentials, VAAPI/NVENC. |

A custom mode lives under `modules.sidecar.custom`:
`delight config set sidecar.custom '{"width":2000,"height":1200,"refresh":90,"scale":1.25}'` then `delight sidecar set preset custom`.

## How it works

- **Display.** `start` reads `hyprctl monitors -j`, takes the focused physical
  monitor as the anchor and computes a position flush against the chosen edge
  and centred on it (in logical pixels, so scale and rotation are respected).
  It applies the rule with `hyprctl eval 'hl.monitor({ output = "DELIGHT-SIDECAR", ... })'`
  *before* `hyprctl output create headless DELIGHT-SIDECAR`, so the output is
  born at the requested mode, then focuses the anchor again. Other monitors are
  never touched. Hyprland lays out `auto`-positioned monitors (Omarchy's
  catch-all rule) after explicit ones, so if an explicit tablet position would
  shove one, Sidecar switches the tablet to `auto-center-right|left|up|down`
  and lets Hyprland place it on that edge instead. The same rule is written to
  `$XDG_RUNTIME_DIR/omarchy-delight/sidecar/monitor.lua`, which this module's
  `hypr.lua` dofiles, so `hyprctl reload` does not snap the tablet back to
  Omarchy's catch-all rule. Nothing is written to `~/.config/hypr`.
- **Stop.** Every workspace on `DELIGHT-SIDECAR` is moved to the anchor (or the
  first remaining monitor) with `hl.dsp.workspace.move`, then the output is
  removed and the runtime rule deleted.
- **Sunshine.** Sunshine streams one output per process. While the sidecar
  runs, the user's own `sunshine.service` (or an autostarted `sunshine`) is
  stopped and `delight-sidecar.service` runs `sunshine output_name=DELIGHT-SIDECAR capture=wlr`.
  Sunshine applies `key=value` arguments on top of `sunshine.conf`, so the
  user's config file is never edited; `stop` restarts whatever was running
  before. `capture=wlr` (wlr-screencopy) is required because KMS capture only
  sees physical connectors; Sunshine matches `output_name` against the Wayland
  output name (older builds only accept an index; set
  `modules.sidecar.sunshine.capture`/`encoder` if needed).
- **Pairing.** Moonlight shows a PIN; the panel (or `delight sidecar pair <PIN>`)
  calls `GET /api/pin` for the pending request and `POST /api/pin`
  `{"pairing_id","pin","name"}` on `https://localhost:47990` with HTTP basic
  auth (older Sunshine: `{"pin","name"}`). The password goes to curl on stdin,
  never argv or QML. Requests without an `Origin`/`Referer` header are exempt
  from Sunshine's CSRF check.
- **Install / uninstall.** If Sunshine is already installed, Delight installs
  nothing for it, opens no ports and writes no credentials, and uninstall
  leaves it exactly as it was. Otherwise it runs `delight_pkg_add sunshine` and
  opens the Moonlight ports via `delight_ufw_allow` (private LANs +
  tailscale0), so uninstall removes both. It doesn't use
  `omarchy-install-service-sunshine`: on Omarchy 4.0.4 that script fails after
  installing the package, and Delight can't undo its firewall, autostart and
  web app changes. Only for a Sunshine
  Delight installed does it create a web UI login (`sunshine --creds delight <random>`).
- **Deskreen** (`install --deskreen`, `set backend deskreen`) runs Deskreen
  instead of Sunshine; the panel shows `http://<lan-ip>:3131` and a QR code and
  says "view-only". Deskreen's Wayland capture goes through the screencast
  portal; pick `DELIGHT-SIDECAR` when it asks.

## Tests

`modules/sidecar/tests/sidecar-test.sh` covers monitor-rule generation,
placement maths, Sunshine override rendering, pairing payloads and the
install/start/stop/uninstall lifecycle against a stubbed `hyprctl`.
`modules/sidecar/tests/live-hyprland.sh` runs the same start/stop against a
real Hyprland when `HYPRLAND_INSTANCE_SIGNATURE` is set (skipped otherwise):
DELIGHT-SIDECAR appears at `2388x1668@120` scale 2, every arrangement leaves the
other monitors where they were, and `stop` removes it. Verified on Hyprland
0.56.2 (Arch container, vkms output `Virtual-1`, seatd).

## Manual hardware script (iPad + Moonlight)

1. `delight sidecar install`, then `delight sidecar doctor` (expect `ok` lines
   for Hyprland, Sunshine, credentials and VAAPI or NVENC).
2. Install Moonlight on the iPad (QR in `delight sidecar open`). Put both on
   the same LAN or tailnet.
3. `delight sidecar start`. `hyprctl monitors -j | jq '.[] | select(.name == "DELIGHT-SIDECAR") | {width, height, refreshRate, scale, x, y}'`
   should show `2388x1668@120`, scale 2, to the right of the focused monitor.
4. In Moonlight, add the PC by IP, note the PIN, type it in the panel and press
   Pair. Moonlight lists the host; open **Desktop**.
5. Extended desktop: drag a window off the right edge of the laptop onto the
   tablet; `SUPER + 1..9` workspace moves follow. Try `set arrangement left` /
   `above` and confirm the pointer crosses the matching edge.
6. Input: tap and drag on the iPad (touch becomes pointer clicks), type with
   the iPad keyboard or a paired keyboard, two-finger scroll.
7. `delight sidecar stop`: the tablet stream ends, its windows land on the
   laptop display, other monitors keep their mode and position, and your own
   Sunshine (if any) is running again.

### Latency measurement

Method: run a millisecond clock (`watch -n0.01 -p date +%S.%N`, or
<https://www.testufo.com/> stopwatch) in a window spanning the laptop and the
tablet, photograph both screens together with a phone at 1/1000 s (or record
240 fps slow motion), and take the difference between the two readings across
at least 10 frames; report the median. Moonlight's statistics overlay
(Settings -> Show performance stats) gives the network + decode share of that.

Result: **not yet measured on hardware** — this module was developed against a
headless Hyprland in CI. Record the median here (device, Wi-Fi band, encoder,
resolution/fps) after the first iPad run.
