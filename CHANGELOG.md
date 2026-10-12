# Changelog

## Unreleased

### Changed

- **iPhone (phone module):** replaced KDE Connect with `delightd` (`daemon/`), Delight's own Rust implementation of Apple's ANCS and AMS Bluetooth LE services. iPhone notifications (with their actions) and media control work with no app on the iPhone and no KDE Connect. Clipboard, SMS, ring and file sending are gone from this module until their native versions land (Universal Clipboard needs the Apple Account bridge; files move to AirDrop). Not yet verified on a real iPhone.

## v0.1.0 — unreleased

First release: macOS-style Continuity features for Omarchy 4, as independent
modules behind one Control Center. See the [manual](docs/manual/README.md).

### Added

- **Core** (#1): `delight` CLI, JSON module contract and schemas, user-level
  `install.sh` / `uninstall.sh` that restore touched files byte-for-byte,
  module template, Omarchy menu and Hyprland integration, private-LAN-only
  firewall helper, CI on Arch.
- **Control Center and design system** (#10): theme-aware QML components,
  one tile per module, live status, keyboard navigation.
- **Share** (#13): AirDrop-style sharing over LocalSend; share sheet on
  `SUPER + SHIFT + CTRL + S`, Nautilus **Share…**, receive notifications,
  optional AirDrop mode on monitor-mode Wi-Fi.
- **Phone and Universal Clipboard** (#9): KDE Connect pairing sheet,
  two-way clipboard, notifications, SMS replies, ring, file sending.
- **Universal Control** (#5): keyboard and mouse sharing with Deskflow
  (share) or Lan Mouse (receive), arrangement panel.
- **AirPlay receiver** (#4): AirPlay 2 audio with shairport-sync and nqptp.
- **Sync** (#7): Syncthing with QR pairing, progress and conflict
  notifications, pause/resume.
- **Continuity Camera** (#15): phone as a named v4l2loopback webcam via
  DroidCam (Iriun opt-in), Wi-Fi and USB.
- **Sidecar** (#14): tablet as a second display with a virtual Hyprland
  output streamed by Sunshine to Moonlight.
- **Instant Hotspot and proximity** (#17): auto-join the phone hotspot,
  optional lock on walk-away over Bluetooth.
- **Test VM** (#6): `vm/up && vm/install-delight main && vm/run-all` boots
  Omarchy 4 under QEMU/KVM and runs the VM tests, including the new
  end-to-end `tests/e2e/vm-continuity.sh`.
- **Research** (#2): Find My, AirPods and NameDrop feasibility notes.
- **Manual**: install, uninstall, one page per feature, troubleshooting and a
  hardware checklist (`docs/manual/`).

### Changed

- `delight sync <verb>` runs the sync module; the old file regeneration is
  now `delight refresh` (#12).
- A module may report `needs-setup` right after `enable` (#16).
- The Control Center plugin is enabled after install and removed from
  `omarchy plugin list` after uninstall (#8); plugin tests run in CI (#11).

### Fixed

- Menu generation on jq 1.6 (#3).

### Known deviations and limitations

- **AirPlay uses `sudo systemctl` directly** to enable the `nqptp` system
  service. The module contract only allows sudo through the package and
  firewall helpers; a shared system-service helper would remove this.
- AirPlay is audio only.
- Phone pairing can't use a QR scan: neither KDE Connect app can scan one.
  The QR on the pairing sheet links to the app download.
- Bluetooth proximity is unreliable with phones that rotate their address;
  `proximity.method: connect` is the fallback.
- SUPER combinations from a remote keyboard may not trigger Omarchy shortcuts.
- Continuity Camera Wi-Fi discovery is best-effort; entering the phone's IP is
  reliable.
- **Not yet tested on real hardware**: every phone, Mac and iPad flow, Sidecar
  latency, hotspot auto-join and the one-hour false-lock run. See
  [docs/manual/hw-checklist.md](docs/manual/hw-checklist.md).
