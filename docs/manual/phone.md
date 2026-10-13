# iPhone

Delight links your iPhone natively over Bluetooth LE, with no app on the
iPhone: notifications with their actions, and media control.

```bash
delight phone install && delight phone enable
delight phone pair
```

**Pairing:** on the iPhone, open **Settings › Bluetooth** and tap this computer,
click **Pair** on the Omarchy notification if the codes match, and allow
notifications on the iPhone. It reconnects on its own after
that.

- **Notifications** from the iPhone appear on the desktop with their actions
  (Decline a call, Clear a message), and close when you clear them on the
  phone.
- **Media:** what's playing shows in the Control Center, with play/pause and
  next.

Needs a Bluetooth adapter. No firewall ports. Calls and Messages are next;
Universal Clipboard needs the experimental Apple Account bridge. Details:
[modules/phone/README.md](../../modules/phone/README.md).
