# Continuity Camera

Continuity Camera presents an Android phone or iPhone as a named V4L2 webcam
device, **Continuity Camera**, using DroidCam and v4l2loopback. Browsers, meeting
apps, and OBS can select that device like any other camera. The module does not
provide a live preview: continuously decoding and drawing a second video stream
would add unnecessary CPU and latency.

## Backends

- **DroidCam** (default): supports Android and iPhone over Wi-Fi; Android also
  supports USB debugging and iPhone supports USB after trusting the computer.
  Use `delight camera connect --wifi <IP>` when discovery is unavailable.
  Discovery is best-effort; the stored IP is the reliable Wi-Fi path. The
  configured mDNS service types are unverified and may differ between app
  versions or networks.
- **Iriun** (opt-in): select it with `delight camera backend iriun`. It starts
  the Iriun GUI in tray mode and discovers phones itself. Iriun writes to its
  own **Iriun Webcam** device; it cannot target **Continuity Camera**, has no
  headless mode, and is not a replacement stream into the named device.
  `iriunwebcam-bin` also installs a package-owned global v4l2loopback options
  file. Delight warns about this and never edits that file.

The DroidCam package owns `/etc/modules-load.d/droidcam.conf`, which requests
`v4l2loopback-dc`. With the regular `v4l2loopback-dkms` module this may produce
a systemd-modules-load failure note. It is package-owned and Delight leaves it
untouched. Delight installs `v4l2loopback-dkms` before the AUR `droidcam`
package; it never installs `v4l2loopback-dc-dkms`.

## Privilege and device lifetime

Creating or deleting a loopback device requires root. On install, Delight
installs a narrowly scoped root path watcher and oneshot reconciliation unit
using `sudo systemctl edit --stdin` (or a system-unit install fallback on older
systemd), then enables the path unit. This requires an administrator once; no
polkit rule or sudoers entry is installed. The user service only creates or
removes its runtime `want` file. The root helper responds to that file and
ensures the module and named device exist while the module is enabled in the
session.

Delight identifies devices by the exact name **Continuity Camera**. It only
deletes a loopback device with that exact name, never unloads v4l2loopback, and
never writes under `/etc/modprobe.d` (or any other `modprobe.d`). This lets the
camera coexist with Omarchy Cam Link: **Cam Link 4K** remains a separate named
device and is never altered.

## Commands

```sh
delight camera install
delight camera enable
delight camera connect
delight camera connect --usb
delight camera connect --wifi 192.168.1.20
delight camera disconnect
delight camera set connection auto|usb|wifi
delight camera set ip 192.168.1.20
delight camera set port 4747
delight camera set size 1280x720
delight camera status --json
delight camera doctor
delight camera open
delight camera disable
delight camera uninstall
```

`auto` tries USB first, then a saved IP, then best-effort mDNS discovery.
`delight camera set backend droidcam|iriun` is also available; the shorthand
`delight camera backend droidcam|iriun` is equivalent.

## Troubleshooting

- Run `delight camera doctor` for package, kernel-header/DKMS, Secure Boot,
  helper-unit, device, and phone checks.
- If the device is not ready, confirm the privileged path unit is enabled and
  inspect `systemctl status delight-camera-loopback-$(id -u).service`.
- If v4l2loopback is unavailable for the running kernel, install the matching
  Omarchy kernel headers and rerun `delight camera install`.
- On Secure Boot systems, signed-module enforcement may require signing the
  DKMS module or disabling enforcement.
- Confirm the phone and computer share a network, or set the phone's current IP
  explicitly. Android USB needs USB debugging; iPhone USB needs the trust
  prompt accepted.
- Select **Continuity Camera** in the app. If using Iriun, select its separate
  **Iriun Webcam** device instead.

## Manual hardware check [HW]

Install the DroidCam phone app:

- Android: [DroidCam Webcam & OBS Camera](https://play.google.com/store/apps/details?id=com.dev47apps.droidcam)
- iPhone: [DroidCam Webcam & OBS Camera](https://apps.apple.com/app/id1510258102)

For each of Android over Wi-Fi, Android over USB, iPhone over Wi-Fi, and iPhone
over USB:

1. Install and open DroidCam on the phone. For USB, enable Android USB
   debugging or trust the computer on iPhone. For Wi-Fi, use the phone's
   displayed address or set it with `delight camera set ip <IP>`.
2. Enable the module and connect:

   ```sh
   delight camera enable
   delight camera connect --wifi <phone-ip>   # Wi-Fi
   delight camera connect --usb               # USB
   ```

3. Check `v4l2loopback-ctl list` shows **Continuity Camera**.
4. Open <https://webcamtests.com> or a Chromium meeting app, choose
   **Continuity Camera**, and verify live video. In OBS, add **Video Capture
   Device (V4L2)** and choose **Continuity Camera**.
5. Run `delight camera disconnect`; verify the disconnect notification and
   that the tile returns to **Connect your phone**.

## Virtual-machine check [VM]

```sh
delight camera install
delight camera enable
v4l2loopback-ctl list
delight camera status --json
sudo v4l2loopback-ctl add -n "Cam Link 4K" -x 1
delight camera disable
v4l2loopback-ctl list
delight camera uninstall
```

The list should show **Continuity Camera** after enable and **needs-setup**
without a phone. After disable, only **Continuity Camera** disappears; the
pre-existing **Cam Link 4K** remains. Uninstall removes the recorded helper
units and module state.
