# Zenbook A16 camera kernel recipe

Bring-up recipe for the cameras on the ASUS Zenbook A16 UX3607OA
(Snapdragon X2 Elite Extreme, Glymur). It builds a Linux 7.3 tree with
the posted Glymur CAMSS/CCI/PM8010 series, the HM1092 driver, and the
only published A16 board nodes.

This directory is not [`modules/camera`](../../modules/camera/README.md).
That module is Continuity Camera (a phone as a USB/Wi-Fi webcam). The
A16 sensors are MIPI CSI-2 devices on Qualcomm CAMSS.

It is also not a daily-driver Omarchy kernel, and it is not face login.
Howdy stays out of scope until an IR stream exists. Windows Hello parity
is not what this recipe produces.

## What was built here

Checked on 11 November 2026, on an x86_64 cloud VM, with
`aarch64-linux-gnu-gcc` 13.3.0, against the vanilla tarball:

`https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3.tar.xz`

sha256 `87363c24f10e06321eb362765521094e94471f6bff8bce2d6b3e40f39f004953`

That is the same tarball `linux-omarchy-aarch64` 7.3-48
(`pkgbuilds/linux-omarchy-aarch64` in omarchy-pkgs) starts from, before
Omarchy's own patch stack.

`build.sh fetch`, `apply`, and `compile` on a clean extract of that tarball applied the series and compiled:

- `drivers/media/i2c/hm1092.o`
- `drivers/mfd/qcom-pm8008.o`
- `drivers/regulator/qcom-pm8008-regulator.o`
- `drivers/phy/qualcomm/phy-qcom-mipi-csi2-core.o`
- `drivers/phy/qualcomm/phy-qcom-mipi-csi2-3ph-dphy.o`
- `drivers/media/platform/qcom/camss/camss.o`
- `arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a16-ux3607oa.dtb`

The dtb contains `himax,hm1092` at address `0x24`, `ovti,ov02c10` at
`0x36`, `qcom,pm8010-i2c` at `0x08` on `i2c@b94000` (the `i2c5` label in
`glymur.dtsi`), and the reset pinctrl nodes `gpio109` and `gpio239`.
Those are the values from the patches below, showing up in the built
dtb. They are not new measurements.

`dtc` also printed `unique_unit_address` warnings for GENI nodes that
are already in the v7.3 SoC dtsi (an I2C and a SPI node sharing an
address). This recipe does not add those nodes.

A bootable `Image`, `modules_install`, a UKI, and a boot on the laptop
were not produced. `makepkg` was not run. The series was not applied on
top of the Omarchy 7.3-48 patch stack. That stack edits `glymur.dtsi`
(USB, LLCC, SMMU, PCIe) and carries A16 EC/Wi-Fi/battery patches
(`2500`, `2501`, `2502`) plus a different board's camera node (Yoga
Slim 7x, `2552`). Expect conflicts there. A tree of vanilla 7.3 plus
only this series does not have Omarchy's scheduler, EC, Wi-Fi, or audio
work. Do not install it over `linux-omarchy` for daily use.

`./build.sh apply /path/to/tree` is the hook for a tree that already has
the Omarchy patches. That combination was not tested.

## What other people have verified

| Claim | Who | Where it stops |
|---|---|---|
| Front RGB sensor streams 1280x720 at 30 fps through libcamera on an A16, on CCI1 bus 1 and CSIPHY4, 2 lanes, with PM8010 I2C series v3 | Christian Cortner, 31 Oct 2026, Tested-by on the Glymur DTS v2 cover for patches 1–3 | The board node was "CRD wiring with ov02c10" and was not posted. Reset GPIO and regulator voltages were not in the mail. [LKML](https://lkml.indiana.edu/2611.0/09819.html), [lore](https://lore.kernel.org/all/179346368177.44447.12360580299773199469.x2e-share-camss-dt@gmail.com/) |
| PM8010 at `0x08` on `i2c5`, no interrupt in DT, probes, and LDO4 plus LDO7 power that front camera | Same tester, on the PM8010 v3 cover | Voltages were not published. [lore](https://lore.kernel.org/all/179346368316.44447.5094215662368347048.x2e-share-pm8010@gmail.com/) |
| `cam_mclk4` at the posted 2 mA bands on this A16 when the DMIC clock runs (LPASS LPI GPIO6, 2.4 MHz). 6 mA on that pin fixes it, A/B/A across three boots | Jesse Casco, 10 Nov 2026, reply to DTS v2 patch 3 | He did not post a patch. The default series keeps the posted 2 mA. Opt in with `APPLY_MCLK4_6MA=1`. [lore](https://lore.kernel.org/all/20261110221232.3883-1-jesse.casco@gmail.com/) |
| HM1092 v8 probes, streams, and does exposure, analogue gain, digital gain while streaming, and runtime PM | Ramshouriesh R, on a Zenbook A14 (Purwa), Qualcomm 24 MHz mode | Not the A16. The ACPI 19.2 MHz mode in patch 3 is the Dell/Intel mode. The A16 should use 24 MHz. |
| Glymur has the OV02C10 and HM1092, on CAMSS, not USB UVC | Windows driver store names `qccamfrontsensor_extension8480.inf` and `qccamauxsensor_extension8480.inf`, recorded by FixItFoundry | Identity of the chips, not the Linux wiring |

Konrad Dybcio Acked-by on DTS v2 patch 1, and asked for the Glymur CCI/CAMSS series to merge without adding A16 nodes in the middle of review. This recipe keeps the A16 nodes in a separate, clearly out-of-tree patch for that reason.

## What is unverified on the A16

The board patch is [FixItFoundry `0108`](https://github.com/FixItFoundry/zenbook-a16-linux/blob/main/patches/stable/0108-arm64-dts-a16-rgb-ir.patch), placed at v7.3 anchors. No register, address, GPIO, or voltage in it was edited. The RGB half matches Cortner's public bus, PHY, and lane count. The rest of `0108` is a hypothesis.

| Item in `0108` | Value carried | Status |
|---|---|---|
| OV02C10 bus and address | `cci1_i2c1` at `0x36` | Matches Cortner's report |
| OV02C10 CSI | CSIPHY4, 2 lanes, 400 MHz link, MCLK4 at 19.2 MHz | Bus, PHY, and lane count match his report. The link frequency and the MCLK rate are the patch's values |
| OV02C10 reset | TLMM 239 | Not in his mail |
| OV02C10 supplies | PM8010 LDO7 at 2.8 V, LDO4 at 1.8 V | He said LDO4 and LDO7 power the front camera. He did not publish the voltages |
| HM1092 bus and address | `cci0_i2c0` at `0x24` | **TODO.** No A16 chip-id read is published. An earlier AeoB note guessed a shared bus; Cortner's RGB result already contradicts that guess. Read the chip id before trusting `0x24` |
| HM1092 reset | TLMM 109, active low | **TODO.** A wrong reset can hold the CCI bus and take the RGB sensor down with it |
| HM1092 supplies | PM8010 LDO3 at 2.8 V (AVDD), LDO4 at 1.8 V (DVDD and DOVDD) | **TODO.** `0108` itself says the PM8010 input rails stay firmware-managed until the supply mapping is verified. Do not raise a voltage to see what happens |
| PM8010 reset | TLMM 106 | Same GPIO number as the CRD patch. Not confirmed on the A16 |
| `leds` | both sensors point at `privacy_led`, TLMM 111, white | This is the privacy indicator already in mainline. It is not an IR illuminator |
| IR illuminator | absent | **TODO.** Windows Hello on this model uses NIR. The A14 strobes a PM8550 flash LED. Do not copy that onto the A16. The evidence log is [`docs/a16-ir-illuminator.md`](../../docs/a16-ir-illuminator.md); collect with `research/a16-ir-illuminator/collect.sh` on Linux and `collect-windows.ps1` on Windows. No pin, address, or current in that note is an A16 illuminator fact |

`APPLY_A16_BOARD=0` stops after the SoC nodes and the drivers, and does not add these sensor nodes.

## How to check each claim

Run this on a kernel that actually contains the series. Stock Omarchy
7.3.0-7, as inspected at the end of October 2026, had no camera nodes,
and earlier builds blacklisted `i2c_qcom_cci`, `qcom_camss`, and
`ov02c10`. A blank result on that kernel means the stack is absent, not
that the sensors are missing. Keep the Windows install.

### A. This is not a UVC webcam

```bash
lsusb
ls /sys/bus/usb/drivers/uvcvideo/ 2>/dev/null
v4l2-ctl --list-devices
```

No UVC camera (or only an external one) is the expected result.
`linux-enable-ir-emitter` and the Intel SVP7500 HM1092 fix pack do not
apply to this machine.

### B. CAMSS and CCI probed

```bash
uname -r
cat /proc/cmdline
lsmod | grep -E 'camss|cci|ov02c10|hm1092'
dmesg | grep -Ei 'camss|cci|ov02c10|hm1092|himax|camcc|pm8010'
ls /sys/bus/platform/devices | grep -Ei 'cci|camss|isp|camcc'
```

Nothing at all: the running DTB does not have the nodes. `camcc`, `cci`,
and `camss` without a sensor: continue.

### C. Which device answers

```bash
media-ctl -d /dev/media0 -p
i2cdetect -l
dmesg | grep -Ei 'hm1092|ov02c10|pm8010|privacy'
ls /sys/class/leds/
```

Identify the CCI adapters from `i2cdetect -l` and scan only those.
Adapter numbers differ by boot. Do not scan unrelated buses.

```bash
sudo i2cdetect -y <cci adapter>
```

| Probe result | What it means |
|---|---|
| `0x36` on `cci1_i2c1` | Matches the confirmed RGB wiring |
| `0x24` on `cci0_i2c0` | Supports the `0108` HM1092 guess. A chip id from the driver is the real check |
| HM1092 on some other bus or address | Change the DTS to match the probe. Do not keep forcing `0x24` |
| No IR chip id | Clock, reset, rail, or bus is wrong. That is a board bring-up cycle |

### D. RGB, the part someone has already streamed

```bash
cam -l
cam -c1 -s width=1280,height=720 --capture=10 --file=rgb-test.frame
```

If RGB fails, stop. IR will not be easier. Horizontal banding that
tracks the microphone clock is the symptom Jesse measured; the 6 mA
override is the opt-in for that, still local.

### E. IR stream, then the illuminator

```bash
media-ctl -p | grep -A20 -i hm1092
cam -l
```

Frames are mono RAW10 (560x360 in the Qualcomm mode), not MJPEG. In a
dark room, a face that stays black means the illuminator is off. A face
that is lit in IR means something already turned it on: record which
rail or GPIO. A phone camera may show the flood as a purple glow. That
is a hint, not a measurement.

There is no illuminator node in this series. Do not mark the privacy
LED as one.

## Where to get the missing wiring

Prefer the ACPI tables the firmware already gave Linux. This works on
stock Omarchy and does not need a partition offset:

```bash
sudo cat /sys/firmware/acpi/tables/DSDT > dsdt.dat
iasl -d dsdt.dat
for t in /sys/firmware/acpi/tables/SSDT*; do
  name=$(basename "$t")
  sudo cat "$t" > "$name.dat"
  iasl -d "$name.dat" || true
done
```

Search the `.dsl` for the camera devices, `I2cSerialBusV2`, and
`GpioIo` / `GpioInt` resources. `iasl` is the ACPICA compiler
(`pacman -S acpica`).

On Windows, ACPICA's `acpidump -b` writes the same tables if the Linux
dump is missing a camera method. The INF names above live in the Windows
driver store and confirm the sensor identities. They do not list the
CCI bus.

A previous AeoB decode is described in FixItFoundry
[`docs/hardware.md`](https://github.com/FixItFoundry/zenbook-a16-linux/blob/main/docs/hardware.md).
It disagreed with Cortner's RGB bus, so treat it as a lead. If a file
starts with the flattened-DT magic `d0 0d fe ed`, decompile it with
`dtc -I dtb -O dts`. This recipe does not guess a partition offset or
a vendor-blob path. `/sys/firmware/devicetree/base` on a running Linux
is the DT that kernel was booted with. On stock Omarchy that tree has
no camera nodes; it is not the vendor DT.

The mainline A16 DTS reserves GPIOs 44–47 and 90 for the TPM. Leave
those ranges alone.

## Build

On the A16, or on any machine with an aarch64 cross compiler:

```bash
./build.sh all /tmp/a16-camera-linux
```

Pieces:

```bash
A16_TARBALL=/path/to/linux-7.3.tar.xz ./build.sh fetch /tmp/a16-camera-linux
./build.sh apply /tmp/a16-camera-linux/linux-7.3
./build.sh compile /tmp/a16-camera-linux/linux-7.3
```

`APPLY_A16_BOARD=0` leaves the sensor nodes out.
`APPLY_MCLK4_6MA=1` adds the 6 mA override on the A16 board file only,
so other Glymur boards keep the posted 2 mA. `A16_FULL_BUILD=1` asks
for `Image`, `dtbs`, and `modules`. That target was not run here.

`PKGBUILD` is the same apply step for an aarch64 Omarchy machine, run
from this directory so `build.sh` stays next to it. Default `makepkg`
builds the objects and the dtb. `A16_FULL_BUILD=1 makepkg` is the full
kernel, and it was not executed in this VM. The package does not
`provide` `linux` and is not a replacement for `linux-omarchy`.

## Series

[`series`](series) is the apply order. [`manifest.json`](manifest.json)
records the source URL, author, version, and review status of each
patch.

| Order | What | How it lands on v7.3 |
|---|---|---|
| 001–002 | CSI2 D-PHY driver v17, Bryan O'Donoghue, 3 Sep 2026 | Verbatim. Under review. A later C-PHY series is not included; the A16 RGB link is D-PHY |
| 003–008 | `phy_get_by_of_node` v20, 18 Sep 2026 | Verbatim. Vinod Koul replied "(subset)" on the phy-core portion. Those commits are not in the v7.3 tag. Patches 5–6 teach CAMSS the standalone PHY. Glymur's DTS describes CSIPHY as its own node, and v7.3 CAMSS still ioremaps CSIPHY registers by name, so this series has to come along |
| 009–011 | Glymur CAMSS v4, Nihal Kumar Gupta, 25 Sep 2026 | Verbatim. The cover says Krzysztof Kozlowski's Reviewed-by was collected and that it was rebased on linux-next 20260924. Not in the v7.3 tag. Glymur matches `x1e80100_resources`; the cover says the 3-vs-4 CSIPHY difference is in DT |
| 012–018 | PM8010 I2C v3, Jishnu Prakash, 30 Oct 2026 | Verbatim. Cortner Tested-by for the A16. Konrad asked patch 3 to grow `get_optimum_mode` the way `qcom-rpmh-regulator` does. Jishnu agreed to do that in a later version that is not in the mailbox. v3 is carried as posted |
| 019 | defconfig `CONFIG_VIDEO_OV08X40=m` | Verbatim. This is the CRD sensor from DTS patch 6, not an A16 sensor |
| 020–024 | HM1092 v8, Ramshouriesh R, 25 Oct 2026 | Binding, the new `.c` file, and the ACPI patch apply as posted. Kconfig, Makefile, and MAINTAINERS are a context rebase because v7.3 has no HM1246 to insert after. One local compile fix drops the unused `v4l2_subdev_client_info` argument that next-20261012 added to `get_selection`. v7.3's callback is still `(sd, state, sel)`. No register value changes |
| 025 | CAMSS, CCI, and MCLK nodes from DTS v2 patches 1–3 | Context rebase. Properties are copied from the lore diffs. Anchors move because v7.3 has no `sdc2_default_state`, and a raw `git apply` of patch 1 inserted CAMSS after `usb_mp` (the hunk context was two lines). Opp tables stay where patch 1 pointed, immediately before `soc@0`. CAMSS sits between `evacc` and `dispcc`, in address order. MCLK drive-strength stays 2 |
| 026 | A16 `0108` nodes | Context placement, tag `board`. The posted file does not apply on v7.3 |

Patches that are in the tree and deliberately not applied:

- DTS v2 patch 4 (CRD PM8010). `git apply` fails: v7.3 `glymur-crd.dtsi` has no `sdc2_card_det_n`. Konrad asked for property order and for LDO1/LDO2 to be 1.104 V rather than 1.2 V. Jishnu agreed to a next version that was not in the mailbox. Those voltages were not invented here, and the CRD node is not the A16.
- DTS v2 patch 5 (CRD OV08X40). The diff applies, then references regulators only patch 4 creates. Konrad Reviewed-by. Not the A16 sensor.
- The original HM1092 v8 patch 2 as one mail, because its context hunks do not apply. The C file from it does.

FixItFoundry's other camera patches are not in the default series:
`0027` (PMH0104 LDOs), `0100`–`0102` (a rebase of DTS v1 onto their
tree), `0103` and `0109` (CCI clock tweaks), `0104`/`0105` (a local
PM8010, superseded here by v3), `0106` (their HM1092 snapshot,
superseded by v8), and `0107` (a local limit of Glymur CAMSS to
CSID0/VFE0). `0107` may matter if probe fails on a secure resource or
the extra PHY. It is not applied blindly, and it is not "the IR camera
works."

## Safety

A wrong reset GPIO can break the bus the RGB sensor is on. A wrong
voltage can damage a sensor. The 2.8 V and 1.8 V numbers are copied
from `0108`, which marks its own input-rail mapping as unverified.
Nothing in this directory raises them, invents a new GPIO, or wires an
illuminator.
