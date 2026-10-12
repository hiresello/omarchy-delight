# Instant Hotspot and proximity

Joins your phone's hotspot automatically when there is no other Wi-Fi, and
can lock the session when the phone goes away.

```bash
delight hotspot install
delight hotspot setup       # pick the saved hotspot connection and the phone
delight hotspot enable
```

`setup` raises the hotspot connection's autoconnect priority above your home
Wi-Fi and marks it metered. Uninstall puts both back.

Proximity uses Bluetooth. Set `hints.away` to `lock` to lock the session when
the phone is out of range; coming back never unlocks it. Phones rotate their
Bluetooth address and seldom answer scans when idle; if proximity never sees
your phone, set `proximity.method` to `connect`:

```bash
delight config set hotspot.proximity.method connect
```

Without a Bluetooth adapter the tile says **Unsupported**. Details:
[modules/hotspot/README.md](../../modules/hotspot/README.md).
