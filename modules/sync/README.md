# sync

Syncthing file sync for Omarchy Delight, with QR pairing for phones. Delight
runs the stock `syncthing.service` user unit and talks to its REST API; your
folders, keys and index stay Syncthing's own and survive `uninstall`.

```bash
delight sync install      # syncthing package, unit drop-in, firewall rules, pairing sheet
delight sync enable       # start Syncthing, create ~/Sync, keep the API on 127.0.0.1
delight sync pair         # QR code + pending requests (sheet, or the terminal with --terminal)
delight sync add-folder ~/Photos --share-with pixel
delight sync toggle       # pause / resume every device (off/on while Syncthing is down)
delight sync status       # up to date · syncing n% · paused · n conflicts · device disconnected
delight sync doctor
```

## What it touches

| Thing | Where | On uninstall |
| --- | --- | --- |
| `syncthing` package | `omarchy-pkg-add` | removed only if Delight installed it |
| Drop-in for `syncthing.service` | `~/.config/systemd/user/syncthing.service.d/delight-sync.conf` (`PartOf=delight.target`, `STGUIADDRESS=127.0.0.1:8384`) | removed |
| `delight-sync.service` | status + notification watcher (`delight sync watch`) | removed |
| ufw | 22000/tcp, 22000/udp (sync), 21027/udp (LAN discovery) from 10/8, 172.16/12, 192.168/16 and `tailscale0`, comment `omarchy-delight:sync` | revoked |
| Syncthing config | REST only: GUI address forced to loopback, default folder created once, devices/folders you add | **kept** |
| `~/Sync`, `~/.local/state/syncthing` | | **kept** |

`syncthing.service` is stopped on `disable`/`uninstall` only if Delight was the
one that enabled it. The API key is read from `config.xml` (Syncthing 2.x:
`~/.local/state/syncthing/`; an existing legacy `~/.config/syncthing/` wins).

## Settings

`delight config set sync.<key> <value>` (defaults in `defaults.json`):

| Key | Default | |
| --- | --- | --- |
| `defaultFolder` | `~/Sync` | created and shared on first `enable` |
| `defaultFolderId` / `defaultFolderLabel` | `default` / `Sync` | Syncthing folder id/label |
| `shareDefaultFolderOnAccept` | `true` | accepting a device shares the default folder with it |
| `apiAddress` | `127.0.0.1:8384` | must match the drop-in |
| `notifyDevices` / `notifyConflicts` | `true` | notifications from the watcher |

## Phones and tablets

- **Android: [Syncthing-Fork](https://github.com/researchxxl/syncthing-android)**
  ([F-Droid](https://f-droid.org/packages/com.github.catfriend1.syncthingfork/)). The official `syncthing-android` app was discontinued in
  December 2024; the fork is the maintained wrapper.
- **iOS / iPadOS: [Synctrain](https://github.com/pixelspark/sushitrain)**
  (free, open source, App Store) — syncs on demand, since iOS does not allow a
  permanent background daemon. **Möbius Sync** (paid) is the long-standing
  alternative.

## Manual test script (hardware)

1. `delight sync install && delight sync enable`; `systemctl --user is-active syncthing`
   prints `active`; `ss -ltnp | grep 8384` shows `127.0.0.1:8384` only;
   `sudo ufw status | grep omarchy-delight:sync` lists private ranges only.
2. **Pair via QR (Android).** `delight sync pair`. In Syncthing-Fork: Devices →
   `+` → scan the QR. Within a few seconds a "New device wants to sync"
   notification appears and the sheet lists the phone; press **Accept**. The
   phone then offers the `Sync` folder; accept it there.
3. **Propagation.** Copy a photo into `~/Sync`; it appears on the phone. Create
   a file on the phone; it appears in `~/Sync`. The Control Center tile shows
   "Syncing n%" during transfers and "Up to date" after.
4. **Conflict.** Turn on airplane mode, edit `~/Sync/note.txt` on both sides,
   reconnect. A "Sync conflict" notification appears; clicking it opens the
   folder containing `note.sync-conflict-*.txt`, and the tile shows "1 conflict"
   until the conflict copy is deleted.
5. `delight sync toggle` → tile shows "Paused", the phone shows the laptop
   disconnected; toggle again to resume.
6. `delight sync uninstall` → drop-in and ufw rules gone, `~/Sync` and
   `~/.local/state/syncthing` untouched.

## Troubleshooting

- **Tile stuck on "Starting…"** — `journalctl --user -u syncthing -e`. A stale
  lock or a second Syncthing instance (e.g. started by hand) is the usual cause.
- **Phone never shows up** — both on the same LAN or tailnet? `delight sync doctor`
  checks the ufw rules; guest Wi-Fi often blocks client-to-client traffic. Off
  the LAN Syncthing falls back to global discovery and relays (slower).
- **"Syncthing API not reachable"** — the drop-in pins the API to
  `127.0.0.1:8384`; if another app holds that port, change `apiAddress` and the
  drop-in together, or free the port.
- **Want the web GUI?** `delight sync open` (loopback only; never expose it).
- **Conflicts** — Syncthing keeps the newer edit and renames the other to
  `*.sync-conflict-<date>-<time>-<device>.*`; delete or merge it and the count
  clears.
- **Start from scratch** — `delight sync uninstall` keeps Syncthing's identity;
  remove `~/.local/state/syncthing` yourself if you want a new device ID.
