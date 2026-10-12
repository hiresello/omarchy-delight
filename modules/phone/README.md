# Phone

Phone links Omarchy Delight to Android and iOS devices through KDE Connect. It provides device status, Universal Clipboard, file and URL sharing, pairing, phone ringing, notification mirroring, and Android SMS conversations.

## Install and use

```bash
delight phone install
delight phone enable
delight phone pair
```

Install KDE Connect on the phone, connect both devices to the same Wi-Fi, select this computer in the phone app, compare the verification key, and accept the request in the pairing sheet. Android can also add the computer by IP using the private addresses shown there.

Useful commands:

```text
delight phone status --json
delight phone devices --json
delight phone share-targets --json
delight phone send phone:<device-id> <path-or-URL>...
delight phone ring [device-id]
delight phone clipboard on|off|send
delight phone sms list --json [--device id]
delight phone sms thread <thread-id> --json [--device id]
delight phone sms reply <thread-id> <text>
delight phone sms send <number> <text>
delight phone sms open
delight phone doctor
delight phone disable
delight phone uninstall
```

`delight phone open` opens the panel. `SUPER + CTRL + ALT + M` is also bound to open it.

## Delight providers

The module provides `devices` records for the Delight device aggregator and `share-targets` for the cross-module sharing picker. Only reachable paired devices with KDE Connect's share plugin loaded are listed as share targets.

## Installed files and lifecycle

The module installs KDE Connect and `qrencode`, the `delight-phone.service` daemon and `delight-phone-bridge.service` event listener, and KDE Connect's TCP/UDP ports 1714-1764 for private networks. It installs three user-level files:

- `~/.config/autostart/org.kde.kdeconnect.daemon.desktop` hides the upstream autostart entry to prevent a second daemon.
- `~/.local/share/dbus-1/services/org.kde.kdeconnect.service` redirects D-Bus activation to the Delight systemd service.
- `~/.config/kdeconnect.notifyrc` suppresses KDE Connect's duplicate notification popups.

Files already present before installation are preserved and not recorded as module-owned. A pre-existing `kdeconnect.notifyrc` may allow duplicate KDE Connect popups; `delight phone doctor` warns about that. Uninstall removes only recorded module files, units, firewall rules, and packages. Packages that were already installed are not removed.

## Clipboard

Clipboard synchronization uses KDE Connect's native clipboard plugin. The daemon is forced onto Qt's Wayland platform plugin so it can use Wayland data-control protocols supported by Hyprland. KDE Connect filters password-manager clipboard entries and prevents clipboard loops. No `wl-paste` bridge is used. On iOS, clipboard synchronization is available while KDE Connect is in the foreground; iOS may suspend background apps.

The doctor checks the daemon journal for KDE Connect's QtClipboard fallback message. That fallback is not suitable for a background daemon and indicates that native clipboard access is unavailable in the current session.

## Notifications and SMS

Android phone notifications are mirrored through `delight_notify`. Dismissing a mirrored notification on the computer asks KDE Connect to dismiss it on the phone; dismissing it on the phone closes the desktop notification. Silent notifications are skipped. Notification synchronization is controlled by the `notifications` default.

SMS conversations are read from the Android KDE Connect app and cached under `$XDG_RUNTIME_DIR/omarchy-delight/phone/sms/` while the bridge runs. Replies and new messages use KDE Connect's conversations D-Bus interface. SMS is not available on iOS or other limited devices; those operations report `SMS needs the Android app`.

## Device support

| Capability | Android | iOS |
| --- | --- | --- |
| Pairing, discovery, battery | Yes | Yes |
| Clipboard | Yes | Yes, while the app is foregrounded |
| Send files, text, and URLs | Yes | Yes |
| Receive files, text, and URLs | Yes | Yes |
| Notifications | Yes | No; iOS does not expose other apps' notifications |
| SMS | Yes | No |
| Ring the phone from the computer | Yes | The iOS app handles the Find My Phone request and presents an alert; hardware behavior has not been tested here |
| Ring the computer from the phone | Yes | Yes |
| Background clipboard | Yes | No; iOS may suspend background apps |

Devices lacking both the `kdeconnect_sms` and `kdeconnect_notifications` plugins are shown as limited. They still support their available pairing, sharing, clipboard, battery, and Find My Phone features.

## Firewall

KDE Connect uses TCP and UDP ports 1714-1764. Delight's UFW rules are restricted to the private IPv4 networks used by the shared firewall helper; the module does not open those ports to the public internet. If UFW is installed, the doctor checks for the module's rules.

## Acceptance checks

### [HW] Phone acceptance

1. Pair an Android phone and confirm its name and battery appear in `delight phone status --json`.
2. Copy text in both directions and confirm it arrives in under two seconds.
3. Send an Android notification, verify it appears on the computer, then dismiss it on each side and confirm it closes on the other.
4. Reply to an SMS from the Messages panel.
5. Use Ring and confirm the phone rings.
6. Confirm `delight share-targets --json` lists the phone, then send a file through `delight share-targets` and verify it arrives.
7. Pair an iPhone and verify foreground clipboard synchronization and file sending.
8. From a connected iPhone, use Find My Phone on the phone to confirm the computer is alerted. The reverse direction is implemented in the checked iOS source, but should be verified on hardware.

### [VM] Install acceptance

1. Run `delight phone install && delight phone enable`.
2. Confirm `systemctl --user is-active delight-phone.service` reports `active`.
3. With UFW enabled, confirm `sudo ufw status | grep omarchy-delight:phone` lists TCP and UDP 1714:1764 rules restricted to `10/8`, `172.16/12`, and `192.168/16`.
4. Run `delight phone pair` and confirm the pairing sheet opens with the QR code and private addresses.
5. Run `delight phone uninstall`; verify the units, firewall rules, and module-owned files are removed, and KDE Connect is removed only if Delight installed it.
