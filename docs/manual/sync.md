# Sync

Keeps `~/Sync` in sync with your phone and other computers using
[Syncthing](https://syncthing.net).

```bash
delight sync install && delight sync enable
delight sync pair
```

**Pairing a phone:** in Syncthing-Fork (Android) or Möbius Sync (iPhone),
add a device and scan the QR on the pairing sheet. Accept the "New device
wants to sync" notification, then accept the `Sync` folder on the phone.

- The tile shows "Syncing n%" during transfers, "Up to date" after, and
  "n conflict(s)" when both sides edited the same file; the conflict
  notification opens the folder.
- `delight sync toggle` pauses and resumes syncing.
- The Syncthing web UI listens on `127.0.0.1:8384` only.
- Uninstall removes Delight's drop-in and firewall rules and leaves `~/Sync`
  and Syncthing's state untouched.

Details: [modules/sync/README.md](../../modules/sync/README.md).
