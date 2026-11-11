# Research

Owned by the `research` track. One directory per topic
(`research/<topic>/README.md`) with findings, links and a recommendation.

| Topic | Recommendation |
| --- | --- |
| [find-my](find-my/README.md) | Go: experimental, opt-in "find this laptop" |
| [airpods-switching](airpods-switching/README.md) | Go: battery, in-ear, one-click connect; no-go on Apple-parity auto-switch |
| [namedrop](namedrop/README.md) | No-go on NameDrop interop; go on QR/NFC vCard "Share my card" |
| [a16-ir-illuminator](a16-ir-illuminator/README.md) | Unknown. Collect evidence before any illuminator patch. |
| [face](face/README.md) | Inventory only: `delight face probe`. No Howdy, PAM, or kernel work from this tree |

The Zenbook A16 camera kernel recipe lives in [`kernel/a16-camera`](../kernel/a16-camera/README.md). It is a kernel bring-up, not a research topic and not face login. It does not wire the IR illuminator; that stays in the note above until a rail is identified. The on-demand IR bridge is the `face` module, separate from this inventory.
