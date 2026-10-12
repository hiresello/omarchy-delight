# Universal Control (input)

Share this computer's keyboard and mouse with neighbouring machines — a Mac,
a Windows box, or another Linux computer — so one desk feels like one computer.
Two backends are supported:

- **Deskflow** (the maintained Synergy fork). On Wayland it shares and receives
  input through the xdg-desktop-portal `InputCapture`/`RemoteDesktop`
  interfaces over libei. Port `24800/tcp`, TLS with per-peer fingerprints.
- **Lan Mouse**. A Rust KVM-style tool that captures input via a layer-shell
  surface and emulates it through wlroots — no portal needed. Port
  `4242/udp`, DTLS with authorized fingerprints.

## Backend selection

`delight input enable` picks a backend automatically (or force one with
`--backend deskflow|lan-mouse`):

| Role | InputCapture portal | RemoteDesktop portal | Backend | Why |
|---|---|---|---|---|
| share | present | — | Deskflow | `deskflow-core server` drives the portal's InputCapture via libei |
| share | missing | — | Lan Mouse | layer-shell capture + wlroots emulation need no portal |
| receive | — | present | Deskflow | `deskflow-core client` receives input via RemoteDesktop/libei |
| receive | — | missing | Lan Mouse | xdg-desktop-portal-hyprland has no RemoteDesktop portal |

xdg-desktop-portal-hyprland 1.4.x implements `InputCapture` (merged upstream),
so **sharing works out of the box**. `RemoteDesktop` is *not* implemented by
xdg-desktop-portal-hyprland (see upstream PRs #308, #402, #426, #428), so
receiving falls back to Lan Mouse automatically.

## Usage

```bash
delight input install                 # packages, unit, firewall, plugin
delight input enable --role share     # or: --role receive [--backend deskflow]
delight input doctor                  # portal findings, backend, fingerprint
delight ui summon delight.input       # arrange neighbours on screen edges

delight input set-peers '[{"name":"mac","host":"mac.local","edge":"right"}]'
delight input trust mac aa:bb:cc:...  # record a peer's TLS fingerprint
delight input fingerprint --json      # our local TLS fingerprint
```

Peers are machines on a screen edge (`left|right|top|bottom`); move the pointer
across the edge to control them. Peer names must match `^[A-Za-z0-9._-]+$`
(the screen name the peer advertises).

## Files and ports

Generated under `~/.config/omarchy-delight/input/`:

- `deskflow/Deskflow.conf` — deskflow-core settings (`-s` file)
- `deskflow/deskflow-server.conf` — screens/links/options (share role)
- `deskflow/tls/` — `deskflow.pem` plus `trusted-clients`/`trusted-servers`
- `lan-mouse/config.toml` + `lan-mouse.pem` (created by the daemon)
- `backend`, `selection.json` — what `run` and `status` use

Firewall: `24800/tcp` (Deskflow) and `4242/udp` (Lan Mouse), allowed only from
`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` and `tailscale0` when present.

## Releasing a grabbed keyboard/mouse

- Deskflow (InputCapture portal): **SUPER + CTRL + ALT + ESCAPE**, bound in this
  module's `hypr.lua` with `allow_input_capture = true`, calls Hyprland's
  `release_input_capture` dispatcher.
- Lan Mouse: its own release chord **Ctrl + Shift + Super + Alt** (the
  `release_bind` default).

## Modifier keys

Hyprland treats keys coming from *virtual* keyboards — Lan Mouse's wlroots
emulation, or a Deskflow client session — differently from physical ones.
SUPER chords sent from the peer may not trigger Omarchy's SUPER bindings. On
macOS, map Cmd to Ctrl in the peer's settings (or macOS's own modifier
remapping) and use the physical keyboard for Omarchy bindings.

## Setting up a peer

### macOS

- **Deskflow**: install the `.dmg` from the deskflow GitHub releases, run it as
  a client, enter this computer's hostname, and accept the server fingerprint
  shown — it must match `delight input fingerprint`. Grant the app
  Accessibility access when prompted.
- **Lan Mouse**: `brew install lan-mouse` (or a release build), add this
  computer on the *opposite* edge, and authorize fingerprints on both sides.

### Windows

- **Deskflow**: run the installer, client mode, enter this computer's
  hostname, accept the fingerprint. Allow `24800/tcp` through Windows
  Firewall.
- **Lan Mouse**: unzip the release build, add this computer on the opposite
  edge, authorize fingerprints both ways.

## Manual hardware test

A. **Omarchy → Mac, Deskflow server** (`enable --role share`, Mac as client):
   1. Pointer crosses the configured screen edge onto the Mac and back.
   2. Typing follows the pointer on both machines.
   3. Text clipboard copies both ways.
   4. SUPER + CTRL + ALT + ESCAPE on the Omarchy keyboard releases a capture.

B. **Omarchy receiving, Lan Mouse** (`enable --role receive`, Mac runs Lan
   Mouse with Omarchy on an edge):
   1. Pointer and typing arrive on Omarchy when the Mac crosses the edge.
   2. Ctrl + Shift + Super + Alt on the Mac returns control to it.

C. **Uninstall**: `sudo ufw status | grep omarchy-delight:input` prints
   nothing, and `~/.config/omarchy-delight/input` is gone.

## Advanced: third-party RemoteDesktop bridge portals

Community portal backends exist that implement `org.freedesktop.portal.
RemoteDesktop` on wlroots/Hyprland. With one installed, Deskflow client mode
works and `--backend deskflow --role receive` is how to opt in. Delight never
installs them and never edits the system portal configuration — doing so is
entirely the user's choice.
