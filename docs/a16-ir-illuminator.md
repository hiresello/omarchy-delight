# A16 IR illuminator

**Machine:** ASUS Zenbook A16 UX3607OA, Snapdragon X2 Elite Extreme (`glymur`)
**Date:** 11 November 2026
**Status:** research. No pin number, I2C address, or current in this note is an A16 illuminator fact unless a source measured it on this board. None has.

The companion scripts are [`research/a16-ir-illuminator/collect.sh`](../research/a16-ir-illuminator/collect.sh) and [`collect-windows.ps1`](../research/a16-ir-illuminator/collect-windows.ps1). They only read.

## Verdict

Windows Hello on this laptop needs a near-infrared flood. Linux has no known way to turn that flood on. The out-of-tree FixItFoundry device tree wires the white privacy indicator, which is a different LED.

The closest published design is the Zenbook A14 (Purwa, previous Snapdragon generation): a PM8550 flash-LED channel, strobed in software while the Himax HM1092 streams. That PMIC is not the A16's PMIC. On Glymur, Qualcomm's own PMH0101 flash-LED block is present in the SoC device tree and **disabled, with an explicit statement that Glymur boards do not use it**. So the A14 wiring is a template for the *shape* of the problem (a current source the host turns on for the duration of a capture) and not a register map for this laptop.

What remains unknown, until Juan runs the scripts on the machine:

- Which part sinks the LED current (discrete LED driver, a GPIO, the sensor's own LED pin, or a PMIC channel nobody has named).
- Any address, GPIO number, or current limit for that part.
- Whether the HM1092 on this board even answers on I2C. The bus and address are still a hypothesis (see below).
- Whether the flood is on for the whole capture, pulsed, or gated inside the module.
- Whether Windows turns it on from the camera stack, the EC, or both.

## What is already known

| Fact | Source |
|---|---|
| Retail UX3607OA lists an IR webcam for Windows Hello. | [ASUS tech specs](https://www.asus.com/us/laptops/for-home/zenbook/asus-zenbook-a16-ux3607/techspec/) |
| Front sensor is OmniVision OV02C10. Aux/IR sensor is Himax HM1092. Names come from `qccamfrontsensor_extension8480.inf` and `qccamauxsensor_extension8480.inf`. | [FixItFoundry hardware notes](https://github.com/FixItFoundry/zenbook-a16-linux/blob/main/docs/hardware.md) |
| Both are MIPI CSI-2 behind CAMSS, not USB. `linux-enable-ir-emitter` drives UVC cameras and has nothing to talk to here. | Same notes; HM1092 cover letter |
| HM1092 product page: 1-lane MIPI, RAW8/10, and "Provide LED control signal to sync with rolling shutter exposure." No public pin number or register for that signal. | [Himax HM1092](https://www.himax.com.tw/products/cmos-image-sensor/image-sensors/hm1092/) |
| Mainline-style A16 DTS has three GPIO LEDs: keyboard camera (TLMM 120, orange), mic mute (TLMM 98), privacy (TLMM 111, white). No camera sensor node and no flash LED. | [glymur-asus-zenbook-a16-ux3607oa.dts](https://git.yoctoproject.org/linux-yocto-dev/plain/arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a16-ux3607oa.dts) |
| FixItFoundry [`0108`](https://github.com/FixItFoundry/zenbook-a16-linux/blob/main/patches/stable/0108-arm64-dts-a16-rgb-ir.patch) sets `leds = <&privacy_led>` on both sensors. That phandle is the white TLMM 111 indicator. | The patch |
| HM1092 driver v8 (25 October 2026), the series under review, does not strobe an LED. Exposure text mentions "illuminated captures" on an A14, meaning the lab lit the scene. Board wiring was deferred to a later series. | [v8](https://patchew.org/linux/20261025-hm1092-driver-v8-0-9cd575c366cf@gmail.com/) |
| An earlier A14 driver (10 June 2026) did strobe a flash LED at about 10 Hz while streaming, and the matching DTS named PM8550 channel 4: torch 180 mA, flash 700 mA, hardware timeout 1.28 s, `LED_COLOR_ID_IR`. Reviewers told the author to drop the PMIC name from the sensor driver. Those currents and that channel are A14 facts. | [DTS](https://lkml.iu.edu/2606.1/06333.html), [driver](https://lkml.iu.edu/2606.1/06331.html), [review](https://lkml.iu.edu/2606.1/06466.html) |
| PMH0101 (a Glymur PMIC) has a flash-LED node at SPMI `0xee00`, `status = "disabled"`. Jishnu Prakash, 9 October 2025: flash and PWM on PMH0101 are used on Kaanapali, not on Glymur. | [PMIC dtsi review](https://lkml.org/lkml/2025/10/9/799), [binding](https://lists.openwall.net/linux-kernel/2025/09/24/1661) |
| Glymur CRD camera patches add PM8010 LDOs and an OV08X40 on CSIPHY4. No flash LED, no HM1092. PM8010 there is an I2C PMIC at address `0x8` with seven LDOs and a 2-GPIO controller. | [v2 4/6](https://lore.jethome.com/lkml/20261015-glymur_camss_dts-v2-4-e7b1f403146f@oss.qualcomm.com/), [v2 5/6](https://lists.openwall.net/linux-kernel/2026/10/15/1370) |
| AeoB decode of this board's Windows blobs (`CAMF_RES_QRD.bin`, `CAMI_RES_QRD.bin`, BSP 1.312.4500.0) lists MCLKs, CCI pins, resets (aux TLMM 109, front TLMM 239), LDOs, a boost, and points at the existing privacy LED. It does not list an IR flood. That is "not in the published power-sequence table", which is weaker than "the LED does not exist". | [hardware.md](https://github.com/FixItFoundry/zenbook-a16-linux/blob/main/docs/hardware.md) |
| The ASUS Glymur EC driver (A14 and A16) publishes keyboard-backlight mailbox commands, a misc "enable writes" command, fan RPM, temperatures, and events for power and thermals. No camera or IR command. | [asus-glymur-ec v4](https://lkml.iu.edu/2610.1/17495.html) |
| OV02C10 on an A16 streams 1280x720 at 30 fps on CCI1 bus 1 and CSIPHY4, with the PM8010 I2C regulators (Christian Cortner, 31 October 2026). That test did not include the IR sensor or an illuminator. | [LKML](https://lkml.indiana.edu/2611.0/09819.html) |

The HM1092 bus on this laptop is still open, and it matters because a discrete LED driver would sit on a camera I2C bus next to the sensor:

- Patch `0108` puts HM1092 at `0x24` on `cci0_i2c0`.
- The AeoB decode argues both sensors share `cci1_i2c0` (TLMM 105/106).
- Cortner's working RGB test is `cci1_i2c1`, which already disagrees with that shared-bus reading.
- `0108` also uses TLMM 106 as the PM8010 reset, while the AeoB note uses TLMM 106 as CCI SCL.

Treat every one of those as a hypothesis. Do not pick one in a new DTS in order to "find" the LED.

## How other Hello cameras turn the flood on

These are different boards. They show the menus Linux already knows about. They do not identify the A16 part.

### Zenbook A14 (same sensor family, previous SoC)

Host software strobes a PMIC flash LED for the whole stream. The June 2026 driver re-armed the PM8550 every 100 ms with a 50 ms on-time, because that controller's safety timer turns the LED off by itself (1.28 s in that DTS) and a bare re-strobe was a no-op unless brightness and timeout were programmed again. The sensor node pointed at the LED with the generic `leds` property. The author avoided `v4l2_async_register_subdev_sensor()` because that helper treats `leds` as a privacy indicator and would reject a flash phandle.

v8 of the sensor driver no longer contains that strobe. Hans de Goede, 27 September 2026, said he had been sent an off-list snippet that enables an IR flood on a Snapdragon laptop through the existing PMIC flash-LED driver, and asked for a userspace API: flash-LED class device, an auxiliary media-controller link to the IR sensor, and an optional "on while streaming" with a control to disable it. He did not name the laptop. The public A14 DTS is the only Snapdragon snippet that matches that description.

### Surface Laptop 7 (X1E) and ThinkPad T14s Gen 6 (X1E)

Upstream and posted device trees for these machines enable a white camera-indicator GPIO and, where the camera is enabled at all, an RGB sensor plus PM8010 rails. Bryan O'Donoghue's T14s series labels some PM8010 LDOs as "IR sensor" rails (1.2 V, 1.8 V, 2.8 V). That is sensor power, not an LED driver. No IR sensor node and no flash LED are in that series. Lenovo's T14s Gen 6 Linux user guide says the IR function is limited in Linux and to use the regular camera if the picture shows grey lines. Surface Laptop 7's initial DTS has the same white indicator pattern and lists the camera as unsupported; later community work got the OV02C10 streaming and still does not document an IR flood.

### Intel HM1092 laptops (wrong host, same sensor)

Two different illuminators show up, which is why "HM1092" does not imply one wiring:

- ThinkPad X9-14 (Lunar Lake): the illuminator is a TI LM3643 at I2C `0x63` on the sensor's bus. Userspace holds it in torch mode during capture. The author says Windows strobes it from the sensor side, and that no in-kernel driver owns the LM3643. Address `0x63` is that laptop's measurement.
- Dell and other IPU6/IPU7 designs: ACPI INT3472 GPIO type `0x02` is the IR flood. It is a plain on/off GPIO. Hans de Goede's review of the int3472 series says to export it as an LED named for a flood, and that "strobe" in Intel's table does not mean a camera-flash strobe. The sensor driver is not what toggles it.

### ASUS Sonix USB modules (wrong camera)

Howdy users on Vivobook, ProArt, and Zenbook S16 machines with USB ID `3277:0018` found the IR LED is gated by a proximity sensor in the module: it pulses when something moves and stays off when the scene is still. `linux-enable-ir-emitter configure` does not find a UVC control for it and has wedged the USB bus on that chipset. The A16 IR camera is not that USB device. A still-versus-waving test is still worth doing once frames exist, in case this module gates its own LED. It is a low-ranked hypothesis.

## Ranked hypotheses for the A16

Rank is "what to spend the next measurement on", given the public record. A higher rank is not a claim that the wiring is known.

### 1. A host-controlled current source that is not in the A16 DTS

Either a discrete I2C LED driver on a camera bus (the X9 pattern), or a Qualcomm camera-stack flash resource that the published AeoB power-sequence table did not name (the A14 pattern, on some other part than PM8550 channel 4).

Why this is first: every HM1092 laptop with a published illuminator uses a separate current source the host turns on. The white privacy LED is already accounted for. The Glymur PMH0101 flash block is documented as unused, so the likely part is something the CRD device tree never mentions. PM8010, on both the CRD and the A14, supplies sensor rails and a couple of GPIOs; the Linux binding used for it is not a flash-current driver.

Confirm: string hits for `FLASH`, `STROBE`, `LM364`, `AW364`, `led-sources`, `PPP_RESOURCE`, `TLMMGPIO` in `CAMI_RES_QRD.bin`, `com.qti.sensormodule.hm1092.bin`, and any sibling blob in the `qccam*` driver folder. On Linux, after the sensor is powered, an extra address on a CCI adapter that is not the sensor and not PM8010.

Retire: those blobs have no flash or LED record beyond the privacy indicator, and a CCI scan with the camera powered shows only the sensor (and PM8010, if it is on that bus).

### 2. A GPIO enable (TLMM or a PMIC GPIO)

Intel's type `0x02` is this idea. A GPIO can live outside the power-sequence records that were decoded. The AeoB table already names the resets and the privacy LED, so a flood GPIO would be an extra line, not one of those.

Confirm: a GPIO in the blob or the DSDT that is not TLMM 111 (privacy), 120 (keyboard camera), 98 (mic), 109 (aux reset in the AeoB note), 239 (front reset), or the MCLK pins. On a live system, `gpioinfo` / debugfs shows that line change only while Windows Hello or an IR capture is running. Observe it. Do not drive it.

Retire: blob, DSDT, and a capture-time GPIO dump name no such line.

### 3. The HM1092 LED-sync pin, with the switch inside the module

Himax advertises an LED control output locked to the rolling shutter. No public register programs it. The v8 driver, extracted from `com.qti.sensormodule.hm1092.bin` and from Dell's `hm1092.sys`, has no such register. If Windows' init table matches that driver and the flood still tracks the stream, the pin is either unused on this module or enabled by a register the public driver dropped.

Confirm: a register write in the Windows sensor blob that is absent from `hm1092.c` and that correlates with the flood. A phone camera can show the flood as a faint purple glow; that is a hint, not a measurement.

Retire: the Windows init table and the published driver program the same sensor registers, and the flood is clearly owned by a part outside the sensor (hypothesis 1 or 2).

### 4. PMH0101 flash LED, despite the "unused on Glymur" comment

The block exists (`qcom,pmh0101-flash-led` at `0xee00`) and it is the same driver family as the A14's PM8550 flash. An OEM could have wired a channel anyway. Enabling it without a named channel and a named current would put a high-current driver on an unknown load.

Confirm: a Windows resource that names this flash controller or a channel on it, or a debugfs/regmap trace that shows the block leave reset only during IR capture.

Retire: the blobs never mention it, which is the expected result of Prakash's comment. Leave the node disabled.

### 5. An ACPI method

WoA cameras enumerate as ACPI devices (`qccam*.inf`, and on some X Elite machines `ACPI\QCOM0C99` and similar). The pinmux for this platform lives in Qualcomm resource blobs. A DSDT method that toggles the flood is possible and, on the machines above, not how the flood is actually switched.

Confirm: `iasl -d` on the DSDT shows a method whose body references an IR LED, flash, or strobe and that the camera stack calls.

Retire: the DSDT names the camera and has no such method. That is the expected result. Still dump the tables, because the absence is evidence.

### 6. An EC mailbox command

The published A16 EC speaks keyboard backlight, fan, thermal, and charge. The command space is only partly documented (the driver comments say the firmware is a modified Hamoa EC and that a hotkey event exists whose trigger is unknown). An undocumented camera command is possible. Sending mailbox bytes to look for one is how you brick a keyboard controller.

Confirm: strings in the Windows ASUS system service or EC driver that are not the published keyboard-backlight command (`0x01` / `0x81`, `0x87`) and that are logged when Hello starts.

Retire: those binaries have no camera or LED command. Do not probe the EC from Linux.

### 7. A proximity-gated emitter, Sonix style

Documented for USB Sonix `3277:0018` on other ASUS laptops. This A16 sensor is MIPI. Ranked last because the camera family does not match.

Confirm: once HM1092 frames exist, a still scene stays dark and a moving hand lights it, with no Linux LED write and no new I2C traffic.

Retire: `lsusb` has no `3277:0018` (expected), and a still face stays dark until a host-controlled LED is turned on.

## What to collect

Run the Windows script on the installed Windows, and the Linux script on a kernel that has CAMSS and CCI up if you have one. A stock mainline DTB with no camera nodes is still worth collecting: it shows the booted tree, the LED class devices, and the ACPI tables. It cannot prove the sensor is missing.

Do not commit either output directory. `computer.txt` is enough to identify the board; the bundles can also contain firmware tables.

### Windows

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File research\a16-ir-illuminator\collect-windows.ps1
```

Re-run from an elevated PowerShell if `driver-files.txt` is empty. The script:

- records the computer model
- lists camera PnP devices and instance ids
- lists files under DriverStore folders whose names match `qccam`, `hm1092`, `ov02`, `camera`, `aeob`, `sensormodule`
- extracts printable strings matching flash, strobe, LED-driver, PMIC, and TLMM resource tokens
- runs `acpidump -b` only when `acpidump.exe` is already on `PATH`

If `acpidump.exe` is missing, install [ACPICA](https://acpica.org/downloads) and run `acpidump -b`, then `iasl -d` on `dsdt.dat`. The Linux script copies `/sys/firmware/acpi/tables` when that directory exists, which is the same firmware tables.

What to pull out of the bundle by hand:

| File or string | Supports |
|---|---|
| `CAMI_RES_QRD.bin` / `CAMF_RES_QRD.bin` present, and `string-hits.txt` shows `FLASH`, `STROBE`, `LM364`, `AW364`, or a TLMM/PPP resource that is not the known privacy LED | Hypothesis 1 or 2. Keep the blob. Decode the new record before any DTS edit. |
| `com.qti.sensormodule.hm1092.bin` contains a register the v8 driver does not program, next to LED/strobe language | Hypothesis 3 |
| A hit on `pmh0101` together with flash or `led-sources` | Hypothesis 4. Still do not copy the A14 channel or the 700 mA number. |
| DSDT method naming an IR LED | Hypothesis 5 |
| An ASUS EC binary with a mailbox command that is not keyboard backlight | Hypothesis 6. Read it. Do not send it. |
| No hits at all, and the file list actually contains the `qccam*` folder | The power-sequence blobs are the wrong file. Look for a sibling flash/LED blob in that same folder before retiring hypothesis 1. |

Instance ids worth pasting back (they identify the Windows driver, not the pin): anything under Cameras, plus `ACPI\QCOM…` and `ACPI\HIMX…` if present. The A16 stack observed so far uses the `8480` extension INFs, which is the Glymur/X2 generation (`8380` is the previous X Elite generation).

### Linux

```bash
research/a16-ir-illuminator/collect.sh --self-test
research/a16-ir-illuminator/collect.sh
```

Optional, and only after you know which adapters are CCI:

```bash
# probes every address on CCI-named adapters. Do not point this at the EC bus.
research/a16-ir-illuminator/collect.sh --scan-cci
```

If the Windows blobs have been copied to the Linux machine:

```bash
research/a16-ir-illuminator/collect.sh --blobs /path/to/copied-driver-folder
```

The script reads LED brightness, regulator names, `gpioinfo`, `/sys/kernel/debug/gpio`, pinctrl lines that mention cam/led/mclk/cci, the booted FDT (`dtc -I dtb -O dts`), ACPI tables, and a filtered kernel log. It does not write an LED, an I2C register, or a GPIO. `--scan-cci` is the one flag that puts traffic on a bus, and it refuses to run against the self-test fixture.

`/sys/firmware/fdt` on this kind of laptop is the DTB the kernel booted. On current Omarchy that is the kernel's A16 DTB, which we already know has no IR flash node. `dtc` on it is a check that the running tree matches that, not a way to discover a hidden Windows pinmux. The Windows blobs are the vendor description.

Read the bundle in this order:

1. `leds.txt`. The white privacy indicator should be there. A second LED whose name, function, or color says flash or IR would be the first real A16 hit. Its absence is the expected result today.
2. `devicetree-hits.txt` and `running.dts`. Confirm there is still no flash-led consumer.
3. `i2c-adapters.txt`. Note which numbers are CCI. A scan of any other adapter, including the EC, is out of scope.
4. `i2c-scan-cci.txt`, if you ran it. An address is a candidate only when the adapter name is CCI and the sensor rails are on. `0x24` would match the A14 and patch `0108`. It would not by itself be the illuminator. `0x36` is the RGB sensor on the machines that have been posted. `0x63` is the X9's LM3643, not a number to assume here. `0x08` is the Glymur CRD's PM8010. Seeing one of those is evidence about power and the sensor, which you record and do not treat as the LED.
5. `usb.txt`. No `3277:0018` supports retiring the Sonix hypothesis. A UVC IR camera would be a surprise on this model.
6. `kernel-log.txt` and `media.txt`. HM1092 probe lines mean the sensor driver bound. They say nothing about the flood.
7. `acpi/` if present. Search the disassembly for `STROBE`, `FLASH`, `IRLED`, `LED`.

### One observation that needs both OSes

Boot Windows, start Windows Hello enrollment in a dark room, and watch the bezel with a phone camera (the flood often shows as a faint purple glow). Then boot Linux and repeat with the sensor streaming, if it streams. Write down which of these you saw:

- glow on Windows, dark on Linux with the sensor streaming: host control exists and Linux is not exercising it (hypothesis 1, 2, 4, or 6)
- glow on Windows only while a face moves, including a still pause that goes dark: module-side gate (hypothesis 7) or a very short strobe you missed
- no glow on Windows either: the LED is elsewhere in the bezel, the phone cannot see it, or Hello is failing for another reason. Check the privacy shutter.

## If a mechanism shows up: the smallest change

This is a plan for after the bundle names a part. It is not a tested patch, and it must not be applied by copying the A14 numbers.

1. Add a device-tree node only for the part the blobs name. Default the LED off. Take the current limit from the blob or from a later measurement on this board. Leave `pmh0101_flash` disabled unless hypothesis 4 is confirmed, and even then set `led-sources` from the blob, not from the A14's channel 4.
2. Keep TLMM 111 as the white privacy indicator. Do not point the HM1092 `leds` phandle at it in order to light a face. The June 2026 driver would have strobed whatever `leds` referenced, and the V4L2 sensor helper treats that property as a privacy LED.
3. Prefer a userspace or V4L2-flash consumer over a new loop inside `hm1092.c`. v8 dropped the strobe, and the LPC discussion asks for a flash-LED class device plus an auxiliary link to the IR sensor, on while streaming, with a control to turn that behaviour off. A small helper that sets torch brightness at stream start and zero at stream stop matches that, once a real `led_classdev_flash` exists.
4. If the part is an I2C LED driver with a mainline compatible, bind that driver. Do not `i2cset` it from a login script.
5. Whatever turns the LED on has to turn it off when streaming stops, including when the process dies. The A14 author re-fired inside a hardware safety timeout for that reason. An IR LED left in flash mode is an eye hazard and a hardware hazard.

Until step 1 has a name and a current from this board, there is nothing safe to merge.

## What remains unknown

- The A16 component that powers the IR LED, and every electrical parameter of it.
- Whether that component is described in `CAMI_RES_QRD.bin` under a record type the 6 September 2026 AeoB note did not decode.
- The HM1092 I2C bus and address on this board, and whether the chip probes at all.
- Whether the flood is steady, pulsed, or motion-gated on this module.
- Whether a secure-camera / ESS policy in firmware refuses to enable the flood under Linux. That becomes a hypothesis only if the wiring is shown to be correct and the LED still never lights. It is not a conclusion available today.
- A userspace API for laptop IR floods. As of the September 2026 LPC thread, that API was a proposal, not something merged.

## Sources

- ASUS Zenbook A16 specs: https://www.asus.com/us/laptops/for-home/zenbook/asus-zenbook-a16-ux3607/techspec/
- Himax HM1092 product page: https://www.himax.com.tw/products/cmos-image-sensor/image-sensors/hm1092/
- FixItFoundry hardware notes: https://github.com/FixItFoundry/zenbook-a16-linux/blob/main/docs/hardware.md
- FixItFoundry A16 camera DTS: https://github.com/FixItFoundry/zenbook-a16-linux/blob/main/patches/stable/0108-arm64-dts-a16-rgb-ir.patch
- A16 DTS (privacy LED only): https://git.yoctoproject.org/linux-yocto-dev/plain/arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a16-ux3607oa.dts
- A14 HM1092 DTS, PM8550 channel 4: https://lkml.iu.edu/2606.1/06333.html
- A14 HM1092 driver with the strobe loop: https://lkml.iu.edu/2606.1/06331.html
- Review asking to drop the PMIC from the sensor driver: https://lkml.iu.edu/2606.1/06466.html
- HM1092 driver v8 (no illuminator code): https://patchew.org/linux/20261025-hm1092-driver-v8-0-9cd575c366cf@gmail.com/
- PMH0101 flash "not used on Glymur": https://lkml.org/lkml/2025/10/9/799
- PMH0101 flash-LED binding: https://lists.openwall.net/linux-kernel/2025/09/24/1661
- Glymur CRD PM8010: https://lore.jethome.com/lkml/20261015-glymur_camss_dts-v2-4-e7b1f403146f@oss.qualcomm.com/
- Glymur CRD OV08X40, no flash LED: https://lists.openwall.net/linux-kernel/2026/10/15/1370
- A16 OV02C10 Tested-by: https://lkml.indiana.edu/2611.0/09819.html
- ASUS Glymur EC driver: https://lkml.iu.edu/2610.1/17495.html
- IR flood API discussion (LPC): https://lists.libcamera.org/pipermail/libcamera-devel/2026-September/062301.html
- INT3472 GPIO type 0x02 as an IR flood: https://lkml.org/lkml/2026/3/30/1295
- ThinkPad X9 HM1092 and LM3643: https://github.com/meros/hm1092-linux
- T14s PM8010 rails labelled IR and RGB: https://lkml.indiana.edu/2609.0/13651.html
- ThinkPad T14s Gen 6 Linux user guide: https://download.lenovo.com/pccbbs/mobiles_pdf/t14s_gen6_c24_linux_ug_en.pdf
- Surface Laptop 7 (X1) DTS, camera indicator only: https://www.spinics.net/lists/linux-arm-msm/msg206205.html
- Qualcomm SPMI flash-LED binding: https://www.kernel.org/doc/Documentation/devicetree/bindings/leds/qcom%2Cspmi-flash-led.yaml
- Sonix `3277:0018` motion-gated emitter: https://github.com/boltgolt/howdy/issues/1109
