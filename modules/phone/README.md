# iPhone

Delight talks to the iPhone itself, over Bluetooth LE, the way an Apple Watch
or a car does. There is no app on the iPhone and nothing else to install: the
link is `delightd` (`daemon/`), Delight's own Rust implementation of two
services Apple builds into iOS:

- **ANCS** (Apple Notification Center Service): iPhone notifications appear
  on the desktop with their real actions (Accept/Decline for calls, Clear for
  messages), and they disappear when you clear them on the phone.
- **AMS** (Apple Media Service): what's playing on the iPhone shows in the
  Control Center and the phone sheet, with play/pause, next and previous.

```bash
delight phone install && delight phone enable
delight phone pair
```

## How pairing works

`delight phone pair` opens a two-minute pairing window. `delightd` advertises
this computer as a Bluetooth LE peripheral that *solicits* ANCS and AMS, which
is how iOS recognises a notification accessory. On the iPhone, open
**Settings › Bluetooth** and tap this computer. Omarchy shows the pairing
code in a notification: click **Pair** if it matches the iPhone's, then allow
**Share System Notifications** on the iPhone. Outside the pairing window `delightd` rejects
new pairings.

After that the iPhone reconnects on its own whenever it's nearby.

## CLI

| Command | |
|---|---|
| `delight phone pair` | Open the pairing window |
| `delight phone media <play\|pause\|toggle\|next\|previous\|volume-up\|volume-down>` | Control the iPhone's player |
| `delight phone devices --json` | Paired iPhones |
| `delight phone doctor` | Bluetooth, `bluetooth.service` and delightd checks |

`delightd status` prints the daemon's live state; it also writes it to
`$XDG_RUNTIME_DIR/omarchy-delight/delightd.json`, only when it changes.

## Install

`delight phone install` installs `~/.local/lib/omarchy-delight/delightd`: a
local `cargo build` when Rust is present, otherwise the release binary.
`bluez` is the only package; Omarchy already ships it. No firewall ports.

## Not yet

- **Calls (HFP)**, **Messages (MAP)**: next phase.
- **Universal Clipboard, Handoff**: need Apple Account trust; planned as the
  opt-in experimental bridge.
- **Files**: AirDrop, in the share module.

## HW acceptance

Unverified on hardware so far. With an iPhone and a Bluetooth 4.0+ adapter:

1. `delight phone pair`, then on the iPhone **Settings › Bluetooth**: this
   computer is listed. Pairing shows a matching code on both sides. Record
   whether the iPhone lists it at all; if not, note the iOS version.
2. Send yourself a message: it appears on the desktop within 2 s with the
   app name. Clear it on the iPhone: the desktop toast closes.
3. Incoming call: a critical toast with Accept/Decline; Decline rejects the
   call on the iPhone.
4. Play music on the iPhone: the Control Center shows the title;
   `delight phone media toggle` pauses it.
5. Walk out of range and back: it reconnects without pairing again.
6. `systemctl --user stop delight-phone`: toasts from the phone stop and none
   remain on screen.
