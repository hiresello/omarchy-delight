# Sidecar

Use an iPad or Android tablet as a second display. Delight adds a virtual
Hyprland monitor and streams it with Sunshine to the Moonlight app (or
Deskreen, view-only).

```bash
delight sidecar install
delight sidecar open        # panel: QR to install Moonlight, pairing PIN
delight sidecar start
delight sidecar stop
```

1. Install Moonlight on the tablet and put both devices on the same network or
   tailnet.
2. `delight sidecar start` adds a `DELIGHT-SIDECAR` monitor (2388x1668@120,
   scale 2) to the right of the focused monitor. Other monitors don't move.
   Change the side with `delight sidecar set arrangement left|above|below`.
3. In Moonlight, add the PC by IP, type its PIN into the panel, then open
   **Desktop**. Touch works as the pointer.
4. `delight sidecar stop` ends the stream, moves windows back and restarts
   your own Sunshine if you had one.

Latency is not yet measured on hardware. Details:
[modules/sidecar/README.md](../../modules/sidecar/README.md).
