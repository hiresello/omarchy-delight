# IR Face

Optional bridge that lets [Howdy Next](https://github.com/nathawatc/howdy-next) open the ASUS Zenbook A16's Himax HM1092 near-infrared sensor.

The HM1092 is a MIPI CSI-2 camera behind Qualcomm CAMSS. It is not a USB UVC device, so Howdy Next cannot open it as `/dev/videoN`. This module selects that sensor **by name** (`hm1092`) through libcamera, converts the frames to 8-bit grey, and writes them to a named [v4l2loopback](https://github.com/v4l2loopback/v4l2loopback) device while a capture is held.

**Real HM1092 output is unverified.** Nothing in this module has been run against the A16 sensor. `delight face self-test` uses GStreamer's `videotestsrc` and only proves the grey pipeline shape. A passing self-test does not mean the IR camera, the privacy LED, or Howdy Next works on the machine.

This is a convenience capture path. It is not Windows Hello, it does not use a TPM, and it must not be the only way to log in. Howdy Next's own warning applies: keep a password.

## What this module does not do

- It does not patch the kernel, the device tree, or CAMSS.
- It does not probe I2C or invent an HM1092 address.
- It does not turn on the IR illuminator. A dark stream is not a usable login camera.
- It does not install or edit PAM. Another change owns that policy. Do not point PAM at this module until `sudo howdy test` has already succeeded with a recovery shell open.
- It does not install `linux-enable-ir-emitter`. That tool drives UVC cameras. This laptop does not have one.
- It does not touch the Continuity Camera loopback. The device it creates is named **Delight IR** and is the only loopback it deletes.

## Why GStreamer

The bridge is a GStreamer graph:

```text
libcamerasrc camera-name=<hm1092 id> ! videoconvert ! video/x-raw,format=GRAY8 ! v4l2sink
```

`camera-name` is the libcamera id (a path such as `/base/soc/.../hm1092@24`), never a camera index. `v4l2sink` is what actually feeds v4l2loopback in `GRAY8`, which Howdy Next reads as a one-channel frame. The libcamera Python API is not used: it would need a separate V4L2 writer, and the CI stand-in would no longer be the same graph.

CI replaces `libcamerasrc` with `videotestsrc` and `v4l2sink` with `filesink`. That stand-in is explicit. It is not a simulated HM1092.

If libcamera cannot negotiate grey frames (raw mono R10 still needs SoftISP support that was not tested on this sensor), the bridge stops and says so. That failure is expected until a real stream exists. It is not a successful capture.

## On demand

Enabling the module arms a system socket. The socket does **not** open the sensor and does **not** light the privacy LED.

| Command | What it does |
|---|---|
| `delight face hold -- <command>` | Starts the stream, runs the command, then stops the stream. |
| `delight face arm` | Starts the stream and returns. It stops by itself after `maxSeconds` (default 30, hard ceiling 300). |
| `delight face stop` | Stops an armed stream. |
| `delight face _listen` | Enables `delight-face-bridge.socket`. Called when the module is enabled. |

`hold` connects to `/run/omarchy-delight/face-bridge.sock` when that socket exists, which starts `delight-face-bridge@.service` for one connection. The service is not enabled at boot. `RuntimeMaxSec=300` kills a stuck capture so the privacy LED cannot stay on. When the client disconnects, the pipeline exits and the sensor stops.

A PAM stack can call `delight face hold` or `delight face arm` / `delight face stop`. This repository does not install that stack.

The user unit `delight-face.service` only enables and disables the socket. It does not run the bridge.

## Install

From a Delight checkout, as your user:

```bash
modules/face/scripts/install.sh
delight face enable
```

`install.sh` installs the Arch packages declared on the module and is safe to re-run. Repo packages include `libcamera`, `libcamera-tools`, `gst-plugin-libcamera`, GStreamer, `v4l2loopback-dkms`, and `v4l-utils`. `howdy-next` comes from the AUR. Kernel headers for the running kernel are installed first when that kernel package is already present, so the DKMS module has something to build against.

```bash
modules/face/scripts/uninstall.sh
```

Uninstall removes the packages this module recorded, the loopback device named **Delight IR**, the systemd units, and the Howdy fragment. It does not unload `v4l2loopback` and it does not delete any other loopback device.

If `v4l2loopback` cannot be built for the running kernel, install still records the user-level module but skips the system socket and reports `unsupported`. Install again after the matching headers and DKMS build exist.

## Howdy Next

Install writes a fragment to `~/.config/omarchy-delight/face/howdy-next.ini`. It is not a full Howdy config. Do not copy it over `/etc/howdy/config.ini`.

After Howdy Next is installed:

```bash
sudo howdy set device_path /dev/v4l/by-id/delight-ir
```

Howdy Next accepts `/dev/v4l/by-id/…`. The udev rule and the bridge both point that name at the **Delight IR** device. Do not set `device_path` to `/dev/video0` or any other index.

Then, with the module enabled and a kernel where `cam -l` already shows `hm1092`:

```bash
delight face hold -- sudo howdy test
```

`sudo howdy add` is the same shape. Enrolment and a photo spoof check are hardware tests. This module does not perform them.

## Commands

```bash
delight face install
delight face enable
delight face select          # print the hm1092 libcamera id, or fail
delight face self-test       # videotestsrc grey frame; not the sensor
delight face doctor
delight face hold -- <command>
delight face arm
delight face stop
delight face disable
delight face uninstall
```

`select` and `hold` fail with `no IR camera stream:` when no libcamera camera matches `hm1092`, when `cam -l` fails, or when more than one camera matches. They do not fall back to camera 0 or camera 1. `doctor` uses the same rule and does not start the bridge. Exit 3 means the packages are present and the IR stream is not. Exit 0 means libcamera **listed** an id; the frames are still unverified.

`delight face status --json` does not open the sensor. While the module is enabled and idle the subtitle is `Armed — sensor off until a capture`.

## What has to be true on the A16 first

Stock Omarchy may not expose the camera at all (no CAMSS node, or the modules blacklisted). This bridge cannot create that. Before expecting anything but `no IR camera stream`:

1. Boot a kernel where `cam -l` prints a camera whose id contains `hm1092`.
2. Confirm a frame can be captured from that id with `cam` or `qcam`. The picture will be grey. In a dark room the face should be lit in IR. If it is black, the illuminator is off and Howdy will not have a usable image. This module does not switch that light.
3. Only then run `delight face select`, `delight face hold`, and `sudo howdy test`.

Watch the white privacy LED: it should stay off while the module is merely enabled, and it should turn off again when `hold` or `stop` returns. If it stays on, run `delight face stop`. The systemd cap is 300 seconds.

## CI

`modules/face/tests/pipeline-test.sh` runs `delight face self-test`, which writes one 16×16 white `GRAY8` frame through `videotestsrc`. The same test holds a stub pipeline and checks that the GStreamer command contains `camera-name=` for the HM1092 id and `format=GRAY8`, and that it does not contain `camera-index` or the RGB sensor. `selector-test.sh` checks the failure text when the IR camera is absent.

Those tests do not load `v4l2loopback` and do not talk to an HM1092.
