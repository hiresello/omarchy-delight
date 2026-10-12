# AirPlay

AirPlay provides an AirPlay 2 audio receiver for this computer using
`shairport-sync` and `nqptp`. Stream audio from an iPhone, iPad, or Mac, with
track metadata shown in Delight's status tile and a notification when playback
starts.

## Design

Delight runs shairport-sync as a **user unit** so PipeWire output, MPRIS, and
D-Bus use the logged-in user's session. The packaged user unit conflicts with
the Delight unit, and an `ExecStartPre` guard refuses to start while the
packaged system unit is active; the packaged shairport-sync units therefore
cannot run alongside Delight's receiver. `nqptp` remains a **system unit**
because it needs `CAP_NET_BIND_SERVICE` to bind UDP ports 319 and 320.

The receiver publishes its MPRIS and D-Bus interfaces on the session bus. Its
metadata pipe feeds the now-playing tile and sender notification.

## Ports

| Protocol | Ports | Purpose |
|---|---:|---|
| UDP | 319–320 | PTP timing (`nqptp`) |
| TCP | 3689 | DACP remote control |
| UDP and TCP | 5353 | mDNS |
| TCP | 5000 | AirPlay RTSP |
| TCP | 7000 | AirPlay 2 RTSP/HTTP |
| UDP | 6000–6009 | AirPlay audio/control |
| UDP and TCP | 32768–60999 | AirPlay 2 ephemeral streams |

UFW rules are limited to the configured private CIDRs and `tailscale0`.

## Verbs

```text
delight airplay install
delight airplay enable
delight airplay disable
delight airplay toggle
delight airplay status [--json]
delight airplay devices --json
delight airplay rename <name>
delight airplay open
delight airplay doctor
delight airplay uninstall
```

## Files Delight adds

- `~/.config/omarchy-delight/airplay/shairport-sync.conf` — generated receiver
  configuration; change its name with `delight airplay rename`.
- `~/.config/systemd/user/delight-airplay.service` and
  `delight-airplay-metadata.service` — receiver and metadata watcher.
- `$XDG_RUNTIME_DIR/omarchy-delight/airplay/metadata` and
  `now-playing.json` — runtime FIFO and state.
- UFW rules annotated `omarchy-delight:airplay`.
- Install records for packages Delight added and whether Delight enabled
  `nqptp.service`.

Uninstall removes the generated configuration, user units, runtime AirPlay
directory, and recorded UFW rules/packages. It disables `nqptp.service` only
when the install record says Delight enabled it.

## [VM] Verification

```bash
delight airplay install && delight airplay enable
systemctl is-active nqptp.service
systemctl --user is-active delight-airplay.service
avahi-browse -rt _airplay._tcp | grep "<name>"
delight airplay toggle
for _ in {1..5}; do
  avahi-browse -rt _airplay._tcp | grep -q "<name>" || break
  sleep 1
done
sudo ufw status | grep omarchy-delight:airplay
# Confirm sources are only 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16,
# and tailscale0.
delight airplay uninstall
# Confirm no Delight AirPlay units, UFW rules, configuration, or runtime
# files remain, and nqptp is disabled only if Delight enabled it.
```

## [HW] Manual verification

1. On iPhone, open Control Center → AirPlay, select the host name, and play
   Music. Change volume on the phone and confirm the receiver's level changes.
2. Confirm the tile subtitle shows the track and one notification says
   `AirPlay started from <iPhone>`.
3. On Mac, select the receiver through Control Center → Sound → AirPlay, or
   the AirPlay button in Music.
4. Switch sender from iPhone to Mac and confirm playback interrupts cleanly.
5. Run `delight airplay rename "Desk"` and confirm the new name appears on the
   phone within a few seconds.

## Limitations

AirPlay audio only (no video mirroring); no custom panel.
