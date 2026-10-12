# Share (AirDrop-style)

Send files to nearby phones and computers, and receive from them, over
[LocalSend](https://localsend.org). Works with iPhone, Android, macOS, Windows
and Linux devices that run the LocalSend app.

```bash
delight share install && delight share enable
```

- **Share sheet:** `SUPER + SHIFT + CTRL + S`, or right-click files in Files
  (Nautilus) → **Share…**. Pick a device; you get a "Sent" notification.
  (Omarchy already uses `SUPER + ALT + S` and `SUPER + CTRL + S`.)
- **Receiving:** files from a phone arrive with a "Received <name>"
  notification; click it to reveal the file. Text arrives as a notification.
- **From scripts:** `delight share-targets --json` lists every share target
  from every module (LocalSend devices, paired phones);
  `delight share send <target> <paths…>`.
- **AirDrop mode** (`delight share enable --airdrop`) needs a Wi-Fi card with
  monitor mode; otherwise it exits with code 2 and an explanation.

Devices must be on the same private network. Details:
[modules/share/README.md](../../modules/share/README.md).
