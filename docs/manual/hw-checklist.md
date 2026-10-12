# Hardware checklist

One pass over every feature on real devices. Each module's README has the
full script; this page is the order to run them in and the place to record
results. Everything below was **not yet measured on hardware** for v0.1.0:
development and CI used fake system commands, containers with real daemons,
and the Omarchy 4 VM (`tests/e2e/vm-continuity.sh`).

## You need

- An Omarchy 4 laptop with Wi-Fi and Bluetooth, on a private Wi-Fi network.
- An Android phone and an iPhone with LocalSend, KDE Connect, Syncthing-Fork
  (Android) and DroidCam installed.
- A Mac (Deskflow or Lan Mouse; AirPlay sender).
- An iPad with Moonlight.

## Before you start

```bash
pacman -Qe > ~/hw-before.pacman
sudo ufw status verbose > ~/hw-before.ufw
(cd ~/.config/hypr && find . -type f -print0 | sort -z | xargs -0 sha256sum) > ~/hw-before.hypr
~/src/omarchy-delight/install.sh
for id in share phone input airplay sync camera sidecar hotspot; do
  delight "$id" install && delight "$id" enable
done
delight status
```

Every module should be `on`, `needs-setup`, or `unsupported` with a reason.
Open the Control Center (**Delight → Control Center**): one tile per module.

## Checks

| # | Feature | Check | Script |
| --- | --- | --- | --- |
| 1 | Phone | Pair Android; copy text both ways in under 2 s; notification dismiss syncs both ways; SMS reply; ring | [phone README](../../modules/phone/README.md#hw-phone-acceptance) |
| 2 | Phone | Pair iPhone; clipboard with app in foreground; send a file | same, step 7 |
| 3 | Share | From Files → **Share…**, send to each phone; receive a photo from Android | [share README](../../modules/share/README.md#hw-manual-test--real-phones) |
| 4 | AirPlay | Play Music from iPhone; volume follows; switch sender to Mac; rename | [airplay README](../../modules/airplay/README.md#hw-manual-verification) |
| 5 | Universal Control | Pointer and typing cross to the Mac and back; clipboard; release hotkey | [input README](../../modules/input/README.md#manual-hardware-test) |
| 6 | Sync | QR-pair Android; a file round-trips through `~/Sync`; conflict notification; pause | [sync README](../../modules/sync/README.md#manual-test-script-hardware) |
| 7 | Camera | Android and iPhone, Wi-Fi and USB: **Continuity Camera** shows live video in Chromium | [camera README](../../modules/camera/README.md#manual-hardware-check-hw) |
| 8 | Sidecar | iPad extends the desktop; touch and typing work; measure latency | [sidecar README](../../modules/sidecar/README.md#manual-hardware-script-ipad--moonlight) |
| 9 | Hotspot | Home Wi-Fi off: auto-joins the phone hotspot within 30 s | [hotspot README](../../modules/hotspot/README.md#manual-hardware-checks) |
| 10 | Proximity | `hints.away: lock`: walking away locks once, coming back never unlocks; one hour at the desk with no false lock | same, steps 2–3 |

## After

```bash
~/src/omarchy-delight/uninstall.sh
pacman -Qe | diff ~/hw-before.pacman -
sudo ufw status verbose | diff ~/hw-before.ufw -
(cd ~/.config/hypr && find . -type f -print0 | sort -z | xargs -0 sha256sum) | diff ~/hw-before.hypr -
```

All three diffs must be empty.

## Compatibility table

Record each run here (✅ works, ⚠️ works with caveats, ❌ fails, — not tested).

| Feature | Device / OS | Laptop / chipset | Result | Notes | Date |
| --- | --- | --- | --- | --- | --- |
| Phone (clipboard, notifications, SMS) | Android | — | — | not yet measured | — |
| Phone (clipboard, files) | iPhone | — | — | not yet measured | — |
| Share | Android, iPhone | — | — | not yet measured | — |
| AirPlay | iPhone, Mac | — | — | not yet measured | — |
| Universal Control | Mac | — | — | not yet measured | — |
| Sync | Android | — | — | not yet measured | — |
| Continuity Camera (Wi-Fi, USB) | Android, iPhone | — | — | not yet measured | — |
| Sidecar (latency: median ms, Wi-Fi band, encoder) | iPad | — | — | not yet measured | — |
| Instant Hotspot | Android, iPhone | — | — | not yet measured | — |
| Proximity lock (1 h false-lock run) | Android, iPhone | — | — | not yet measured | — |
| Clean uninstall (`pacman -Qe`, `ufw`, `~/.config/hypr`) | — | — | — | not yet measured on hardware; checked in the VM | — |
