# Phone and Universal Clipboard

Links your phone through [KDE Connect](https://kdeconnect.kde.org): shared
clipboard, notifications, SMS replies, file sending, ring and battery.

```bash
delight phone install && delight phone enable
delight phone pair
```

**Pairing:** install KDE Connect on the phone (the QR on the pairing sheet
links to the download), tap this computer in the app, and confirm the key on
the sheet. On Android you can also add the computer by IP. The apps can't scan
a QR to pair.

- **Clipboard** syncs both ways while both devices are connected (iPhone: only
  while the app is in the foreground).
- **Notifications** from the phone appear on the desktop; reply to SMS from
  the Messages panel.
- **Files:** the paired phone appears in the share sheet.

Firewall: TCP and UDP 1714–1764, private ranges only. Details:
[modules/phone/README.md](../../modules/phone/README.md).
