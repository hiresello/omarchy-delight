# Face probe

`delight face probe` is a read-only inventory for infrared face login on the
ASUS Zenbook A16 (UX3607OA). It writes one redacted text file and prints a
plain-language verdict. It does not capture frames, turn an illuminator on,
install Howdy, or edit PAM. The `face` module is a separate on-demand IR
bridge. This probe does not start it.

This page explains how to read that output. The command was checked against
synthetic fixtures in this repository. It has **not** been run on Juan's A16.
Anything it says about a live machine is only as good as the logs from that
boot. Frame capture and illuminator control stay **unverified** until someone
does those steps on the hardware and says so.

The decision tree comes from the A16 feasibility study (11 November 2026).
Short version:

| What the logs show | Verdict id | What to do |
| --- | --- | --- |
| A USB UVC infrared camera | `uvc-ir` | Howdy Next path, after you confirm it is not an external webcam |
| MIPI / CAMSS or OV02C10, and no HM1092 / Himax node | `mipi-rgb-only` | Kernel and device-tree work is still needed for the IR camera |
| An IR sensor node, and no IR capture stream | `mipi-ir-no-stream` | Illuminator or driver issue, not a Howdy setup |
| No UVC IR camera and no MIPI camera stack | `nothing` | The running kernel or device tree is not exposing the cameras. That is not proof the sensors are missing |

Other ids the command can print, so a half-read log is not forced into the
table above:

| Verdict id | Meaning |
| --- | --- |
| `ir-capture-listed` | libcamera or v4l2 lists an IR capture node. Frames and the illuminator were not tested. Stay off Howdy Next until a dark-room capture shows a lit face. |
| `usb-ir-not-uvc` | A USB device name looks infrared, and `uvcvideo` is not bound. Not the Howdy Next path and not the A16 MIPI stack. |
| `incomplete` | A command was missing or the kernel log was unreadable, and the other sections did not prove a camera stack. Do not treat this as "no camera". |

## Run it

On a live USB or an installed Omarchy system, from a checkout of this repo
(or after `install.sh`, so `delight` is on your `PATH`):

```bash
sudo pacman -S --needed usbutils v4l-utils libcamera
delight face probe
```

The report is `./delight-face-probe.txt` (mode `0600`). Pick another path
with `--output`.

If the report says the kernel log was unreadable, re-run so `dmesg` works.
Point `--output` at a file you can read afterwards, because `sudo` may not
keep your home directory:

```bash
sudo "$HOME/.local/bin/delight" face probe --output "$PWD/delight-face-probe.txt"
```

Before `install.sh`, the same command is `./bin/delight face probe`.

The script does not install those packages and does not call `sudo` itself.
`usbutils` provides `lsusb`, `v4l-utils` provides `v4l2-ctl` and `media-ctl`,
and `libcamera` provides `cam`.

## What it collects

- `uname -r`
- `/proc/device-tree/model`
- device-tree nodes whose path or `compatible` string mentions the camera
  stack (`camss`, `cci`, `ov02c10`, `hm1092`, `himax`, and the same family).
  Serial-number nodes are skipped, not copied.
- `/proc/cmdline`, so a camera-module blacklist is visible
- `lsusb`
- whether `/sys/bus/usb/drivers/uvcvideo/` exists, and which interfaces are bound
- `v4l2-ctl --list-devices`
- `media-ctl -d /dev/mediaN -p` for every media node
- `dmesg` lines matching `himax`, `hm1092`, `ov02c10`, `camss`, `cci`, or `pm8010`
  (at most 400 lines)
- `cam -l`
- names under `/sys/class/leds/` (names only)

A privacy LED in that last list is not an IR illuminator. The study's A16
device tree wires the white privacy LED, and the IR flood is a separate,
unidentified control. What is known about that flood, and the read-only
scripts that collect more evidence, are in
[A16 IR illuminator](../a16-ir-illuminator.md).

## What it redacts

The report drops:

- MAC addresses (`aa:bb:…`, dashed, and `aabb.ccdd.eeff`)
- serial-number fields (`SerialNumber`, `iSerial`, `serialno=`, `serial-number`)
- disk `UUID=` and `PARTUUID=` values
- your home directory
- your username when it stands alone

A username that is also a common hardware word (`video`, `camera`, `media`,
`linux`, …) is removed only inside a home path, so `/dev/video0` stays
readable. Usernames shorter than two characters are not scrubbed as bare
words.

Send the report file, not a photo of a serial sticker and not a raw
`dmidecode`. The path printed after `Wrote redacted report:` can contain
your username; delete that line if you paste the terminal.

## How to read the file

The first lines are the verdict. `Verdict id:` is the stable name. The
paragraph under it is the whole decision. `source: live` means this boot.
`source: fixture …` means canned files, which are not hardware evidence.

`Facts:` is the same parse the verdict used:

| Signal | `yes` means |
| --- | --- |
| `uvc_ir` | A USB UVC device whose name looks infrared (word `IR`, `NIR`, `infrared`, `himax`, or `hm1092`), or `lsusb` says that and `uvcvideo` has a bound interface |
| `mipi` | CAMSS, CSIPHY, CCI, or OV02C10 showed up on a platform media graph, in v4l2, in dmesg, or in a device-tree camera node |
| `rgb` | The name `ov02c10` showed up |
| `ir_node` | `hm1092` or `himax` showed up on the MIPI side (not as a UVC device) |
| `ir_stream` | libcamera lists an IR camera with a `WIDTHxHEIGHT` mode, or a non-USB v4l2 device whose name looks infrared has a `/dev/video*` node |
| `pm8010` | The filtered kernel log mentions `pm8010`. Alone, that is not a camera stack |
| `usb_named` | `lsusb` looks infrared and `uvcvideo` has no bound interface |
| `uvcvideo` | `present`, `absent`, or `unknown` |

A generic `/dev/video*` hanging off "Qualcomm Camera Subsystem" is not
counted as an IR stream. On this hardware that node is often the RGB sensor.
`ir_stream=yes` still does **not** mean a frame was captured.

`cmdline camera blacklist:` lists `i2c_qcom_cci`, `qcom_camss`, `ov02c10`,
`hm1092`, or `uvcvideo` when they appear in `module_blacklist=` or
`modprobe.blacklist=`. Those names on the command line do not count as a
probed sensor. The `nothing` verdict calls the blacklist out when it sees one.

The rest of the file is the command output, redacted, in a fixed order.
`(not installed: …)` and `(unreadable: …)` mean that section could not be
read. `(no matching lines)` means `dmesg` ran and the camera filter was empty.

## What to send back

1. The report file.
2. One line on how you booted: live USB or installed system, and whether
   this was stock Omarchy or a kernel you built with camera nodes.
3. If you already know a section was empty because a package was missing,
   say which package. `incomplete` means the same thing inside the file.

Do not send Windows driver dumps, a picture of the laptop's serial, or a
full `journalctl` unless you have read it. Do not install Howdy or edit PAM
from this report. Those steps wait on a real infrared stream and a separate
change.

## What the fixtures are

`research/face/fixtures/` holds four canned trees used by the tests:
`uvc-ir`, `mipi-rgb-only`, `mipi-rgb-ir`, and `nothing`. The model string
and the `7.3.0-7-omarchy` kernel name in `nothing` are labels copied from
the feasibility study so the empty-stack case is recognizable. They were
not read off a machine while writing this command. Re-run a fixture with:

```bash
delight face probe --fixture research/face/fixtures/nothing --output /tmp/face-nothing.txt
```
