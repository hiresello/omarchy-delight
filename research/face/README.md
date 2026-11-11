# A16 infrared face login — inventory probe

Research only. This is not a Delight module, and it is not face login.

The ASUS Zenbook A16 (UX3607OA, Snapdragon X2 Elite Extreme, Glymur) has an
RGB OmniVision OV02C10 and a mono IR Himax HM1092 on MIPI CSI-2 / Qualcomm
CAMSS. They are not USB UVC cameras. A feasibility study (11 November 2026)
says a convenient IR unlock is plausible only after the kernel exposes the
sensor and the illuminator, and that Windows Hello parity is not a Delight
milestone. This directory does not re-check those hardware claims. They stay
**unverified** here.

## Recommendation

Ship a read-only probe first, and do not start Howdy, PAM, or kernel work
from this tree. `delight face probe` collects the logs the study asks for,
redacts serials, MAC addresses, and usernames, and prints one verdict:

| Logs | Verdict |
| --- | --- |
| UVC infrared camera | Howdy Next path (confirm it is not an external webcam) |
| MIPI / RGB and no IR node | Kernel and device-tree work still needed |
| IR node and no capture stream | Illuminator or driver issue |
| No camera stack | Kernel or device tree is not exposing it; not proof the sensors are missing |

How to run it, how to read the file, and what to send back:
[docs/manual/face-probe.md](../../docs/manual/face-probe.md).

The IR flood itself is a separate unknown. Evidence collection for that
part is [a16-ir-illuminator](../a16-ir-illuminator/README.md). This probe
does not replace those scripts.

Synthetic fixtures live in `fixtures/`. Tests are `tests/unit/face-probe.sh`.
Neither was captured on an A16.

## Out of scope

This probe does not install packages and does not open `/dev/video*` for
streaming. Kernel, device tree, and PAM stay outside this directory. The
on-demand IR bridge is the separate `face` module in `modules/face/`.
