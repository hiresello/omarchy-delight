# Instant Hotspot

Instant Hotspot configures a saved NetworkManager Wi-Fi profile for your
phone's personal hotspot, then watches for the paired phone over Bluetooth.
When the phone is nearby, the module can automatically connect to its
hotspot. It can also send a notification, lock the session when the phone
leaves, or wake the display when it returns. Proximity hints are off by
default, and the module never unlocks a session.

## Requirements

- NetworkManager (`nmcli`) manages Wi-Fi and has a saved profile for the phone's
  hotspot.
- Bluetooth is enabled, the phone is paired, and BlueZ exposes its device
  properties.
- `jq`, `busctl`, `bluetoothctl`, and `timeout` are available.
- A user session with the Delight notification, lock, and display helpers is
  needed for the corresponding optional hints.

The phone's hotspot must have been connected to once before setup. On iPhone,
open **Settings → Personal Hotspot** while connecting; iOS may hide or
disable the hotspot when the phone is locked or not in use. Android wording
varies by device, but enable the portable Wi-Fi hotspot and allow the paired
computer to use it; some Android models disable the hotspot after inactivity.

## Setup

Pair and trust the phone with BlueZ first. Connect to its Wi-Fi hotspot once
using NetworkManager so that a saved connection profile exists. Then:

```bash
delight hotspot candidates --json
delight hotspot setup --ssid "Phone hotspot" --bt AA:BB:CC:DD:EE:FF
delight hotspot doctor
```

The Control Center panel offers SSID and phone candidates and setup shortcuts.
From a terminal, an interactive setup can use `gum` to choose candidates:

```bash
delight hotspot setup
```

Setup accepts either the saved Wi-Fi SSID or its connection name. It stores
the selected connection UUID, enables autoconnect, assigns it a priority below
other saved profiles, and marks it metered. The original values are saved and
restored on uninstall or when setup switches to another profile. Use
`--no-enable` to configure the profile without enabling the watcher:

```bash
delight hotspot setup --ssid "Phone hotspot" --bt AA:BB:CC:DD:EE:FF --no-enable
delight hotspot enable
```

The module can be disabled and re-enabled without losing its setup. Run
`delight hotspot connect` for an immediate manual connection, or use
`delight hotspot open` to open its settings surface. `delight hotspot status
--json`, `devices --json`, and `candidates --json` expose the module and
discovery state to the Control Center.

## Proximity and hints

The watcher samples the paired phone's BlueZ RSSI during bounded Bluetooth
discovery windows. RSSI is not always available when the phone is not
discoverable, and BlueZ may suppress small RSSI changes; the hysteresis,
smoothing, dwell times, and suspend-gap reset reduce false transitions.
Bluetooth connection state may be used as a near signal when enabled. The
watcher pauses scanning on low battery while discharging, and resumes when
the battery recovers or AC power is connected.

BlueZ only emits RSSI updates after a change of roughly 8 dBm, so the default
near/away thresholds stay at least 15 dBm apart. iPhones and Android phones
can use rotating Bluetooth addresses and are often not discoverable while
idle; whether BlueZ
resolves a phone's private address through its identity key depends on the
phone and has not been verified across hardware. The optional `connect`
proximity method actively attempts a Bluetooth connection when disconnected;
some phones may route audio to the computer as a result.
On iPhone, Personal Hotspot may only be visible while its Settings page is
open. Android hotspots can stop broadcasting after inactivity.
If scan-based RSSI stays unavailable, try the `connect` method or keep the
phone connected to Bluetooth.

With the defaults, discovery runs for five seconds every 30 seconds (about
17% scan duty while steady); while a proximity transition is pending, scans
can run every 10 seconds. Low-battery pause stops discovery entirely until
charging or recovery above the threshold.

The defaults favor conservative behavior: scan-based proximity, 10 seconds
to confirm arrival, 120 seconds to confirm departure, and both hints off.
Configure `hints.away` as `off`, `notify`, or `lock`; configure
`hints.return` as `off`, `notify`, or `wake`. The notification for leaving
offers a **Lock now?** action; it does not lock unless explicitly selected.
The `lock` hint locks an unlocked session on departure. A return may turn on
the display but will never unlock the session.

## Configuration

The values live under `hotspot` in Delight's configuration:

| Key | Default | Purpose |
|---|---:|---|
| `enabled` | `false` | Run the proximity watcher |
| `ssid` / `connection` | empty | Selected hotspot and saved NetworkManager UUID |
| `phone.mac` / `phone.name` | empty | Paired Bluetooth phone |
| `adapter` | empty | Optional Bluetooth adapter name; empty selects the first available |
| `autoJoin` | `true` | Connect when the phone is near; failures use exponential backoff |
| `proximity.method` | `scan` | `scan` reads RSSI; `connect` attempts a Bluetooth connection |
| `proximity.nearRssi` / `awayRssi` | `-70` / `-85` | Hysteresis thresholds in dBm |
| `proximity.nearDwell` / `awayDwell` | `10` / `120` | Seconds required to confirm presence transitions |
| `proximity.smoothing` / `maxGap` | `0.4` / `300` | RSSI smoothing factor and maximum sample gap in seconds |
| `proximity.connectedIsNear` | `true` | Treat an active Bluetooth connection as near |
| `scan.interval` / `fastInterval` / `window` | `30` / `10` / `5` | Scan cadence and bounded discovery window in seconds |
| `scan.pauseBelowBattery` | `20` | Pause scans below this battery percentage while discharging; `0` disables |
| `backoff.initial` / `max` | `15` / `600` | Autojoin retry delay bounds in seconds |
| `hints.away` | `off` | `off`, `notify`, or `lock` |
| `hints.return` | `off` | `off`, `notify`, or `wake` |

RSSI thresholds and dwell times may need tuning for the particular phone,
adapter, and room. Start with notification-only hints before enabling
automatic locking.

## Troubleshooting and hardware checks

```bash
delight hotspot status --json
delight hotspot doctor
delight hotspot devices --json
delight hotspot candidates --json
journalctl --user -u delight-hotspot -f
```

- **Unsupported / no Bluetooth adapter:** connect a Bluetooth adapter,
  ensure BlueZ is running, and check that it appears under
  `/sys/class/bluetooth`.
- **No saved connection:** connect to the phone's hotspot once, then rerun
  setup with the matching SSID or connection name.
- **Phone is not detected:** confirm it is paired and trusted, keep its
  Bluetooth enabled, and test with the phone unlocked and hotspot settings
  open. RSSI may be unavailable until discovery has started.
- **Autojoin does not connect:** check that Wi-Fi is enabled and that the
  phone's hotspot is currently available. On iPhone, keep Personal Hotspot
  open during initial troubleshooting.
- **False proximity transitions:** increase `proximity.nearDwell` or
  `proximity.awayDwell`, or adjust `proximity.nearRssi` and
  `proximity.awayRssi` for the adapter and room.

Before relying on the feature, test setup and uninstall with a real saved
profile and verify its original autoconnect, priority, and metered values are
restored. Test phone-away behavior with a harmless notification before
enabling an automatic lock hint.

### Manual hardware checks

1. Turn off home Wi-Fi, enable the phone hotspot, and keep the phone nearby.
   Confirm that the saved phone profile auto-connects within 30 seconds:

   ```bash
   journalctl --user -u delight-hotspot -f
   ```

2. Set `hints.away` to `lock`, leave the phone in another room, and confirm
   the session locks once. Return with the phone and confirm the display may
   wake; it must not unlock. Repeat while the session is already locked.
   While scanning, also confirm BlueZ exposes the paired device object and
   determine whether it continues to resolve the phone when its over-the-air
   address rotates; that identity-resolution behavior is not yet verified.

3. At a desk, record and replay an hour of samples. The replay should not
   report an away transition; with the lock hint enabled, also verify that a
   live hour at the desk causes no false lock:

   ```bash
   delight hotspot trace record ~/desk.tsv --duration 3600
   delight hotspot trace replay ~/desk.tsv
   ```

4. Confirm NetworkManager restores the selected profile's original fields
   after uninstall:

   ```bash
   nmcli -f connection.autoconnect-priority,connection.metered c show "Phone hotspot"
   delight hotspot uninstall
   nmcli -f connection.autoconnect-priority,connection.metered c show "Phone hotspot"
   ```

## Diagnostics

`delight hotspot trace record FILE --duration SECONDS` records timestamped
RSSI and connection samples; `trace replay FILE` runs a deterministic sample
through the same proximity state machine without Bluetooth or Wi-Fi side
effects. Traces may contain device-proximity timing, so keep recorded files
private.
