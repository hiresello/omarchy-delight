# AirPlay receiver

Play audio from an iPhone, iPad or Mac to this computer (AirPlay 2, using
shairport-sync and nqptp).

```bash
delight airplay install && delight airplay enable
delight airplay rename "Desk"          # the name senders see
```

On the iPhone: Control Center → AirPlay → pick this computer. The tile shows
the current track and you get an "AirPlay started from <device>" notification.
Toggling the tile off hides the receiver from AirPlay within a few seconds.

AirPlay 2 needs the `nqptp` system service. Enabling the module starts it with
`sudo systemctl` (a known deviation from the module contract, see
[CHANGELOG](../../CHANGELOG.md)); uninstall disables it only if Delight
enabled it.

Firewall: private ranges and `tailscale0` only. Details:
[modules/airplay/README.md](../../modules/airplay/README.md).
