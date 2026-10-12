# NameDrop-like contact exchange

Research only. Nothing here is wired into `install.sh` or any module.

## Recommendation: NO-GO on NameDrop interop; GO on a QR/NFC vCard fallback

No-go: talking to an iPhone's NameDrop from Linux. The protocol is not
publicly documented, is built on AirDrop (AWDL + Apple-signed identity), and
there is no open implementation. Even AirDrop interop on Linux
([OpenDrop][opendrop]) needs an AWDL implementation ([OWL][owl]), a Wi-Fi
card that supports it, and cannot do the "Contacts Only" handshake that
requires Apple-issued certificates.

Go: a "Share my card" feature that produces a vCard and offers it as a QR
code (works with every phone camera, no app), a `.vcf` via the existing share
sheet / phone-module share targets, and optionally an NFC tag/reader path.
Receiving is "save incoming `.vcf`" after explicit confirmation.

## What Apple's NameDrop is (public information)

From Apple's [iPhone User Guide][apple-namedrop]:

- iOS 17+ iPhones and watchOS 10+ Apple Watches share contact cards by
  holding the top of one iPhone near another iPhone or Apple Watch until
  NameDrop appears on both screens.
- The user chooses "Share" (send and receive) or "Receive Only".
- Moving the devices apart or locking the iPhone cancels it.
- Enabled by default; off via Settings > General > AirDrop > Bring Devices
  Together.

Not published by Apple: the wire protocol. Public reverse-engineering
([furiousMAC/continuity][continuity], [Stute et al.][stute19],
[Heinrich et al.][heinrich21]) documents the surrounding Continuity BLE
messages (AirDrop, Nearby Action/Info) and AirDrop over AWDL. The proximity
trigger appears to rely on close-range detection between Apple devices
(likely BLE RSSI and/or UWB on supported models; verify), followed by an
AirDrop-style exchange of the contact poster. There is no public
specification or working third-party implementation we could find
(2026-10).

## What is feasible over BLE / Wi-Fi without Apple's implementation

| Approach | Feasible on Linux? | Interop with iPhone? |
| --- | --- | --- |
| NameDrop proper | No (undocumented, Apple-signed identity) | n/a |
| AirDrop send via OpenDrop + OWL | Partly: needs AWDL-capable Wi-Fi in monitor/injection mode (verify per chip), iPhone set to "Everyone for 10 minutes" | iPhone receives a `.vcf` as a file, no NameDrop UI |
| BLE GATT "contact service" | Yes on Linux, but iPhones have no system handler | Needs an iOS app; no-go |
| Wi-Fi / LAN (LocalSend, KDE Connect) | Yes | Needs an app on the phone; reuse the phone/share modules |
| **QR code of a vCard** | Yes (`qrencode`) | Yes: iOS and Android cameras offer "Add to Contacts" |
| NFC tag with vCard NDEF record | Yes with a USB reader/writer | iPhone background tag reading of vCard records: verify; Android: yes (verify per vendor) |

## Proposed fallback

1. "Share my card" (Control Center action / plugin): build a vCard 3.0 from
   module config (name, phone, email, org, url) and show it as a QR code.
   The phone scans it with the stock camera; no network, no pairing.
2. "Send card to..." via `delight share-targets --json` / `delight send
   <target> card.vcf` so LocalSend/KDE Connect/AirPlay-style targets from
   other modules carry it. No new transport.
3. Receive: when the phone module or share module delivers a `.vcf`, offer
   "Add to contacts" (open in the user's contacts app or save to
   `~/Contacts`) only after confirmation. Never auto-import.
4. Optional NFC: write the same vCard as an NDEF `text/vcard` MIME record to
   a sticker tag or emulate it with an ACR122U-class reader; experimental.

The spike [`spike/vcard-qr.sh`](spike/vcard-qr.sh) builds an RFC 2426
escaped vCard and renders a QR:

```bash
research/namedrop/spike/vcard-qr.sh --self-test
research/namedrop/spike/vcard-qr.sh --name "Ada Lovelace" --tel +441234567890 --email ada@example.com
research/namedrop/spike/vcard-qr.sh --name "Ada Lovelace" --out card.png
```

## What works on Arch today

Verified on archlinux.org / aur.archlinux.org (2026-10).

| Package | Source | Purpose |
| --- | --- | --- |
| `qrencode` | repo (`extra`) | Render vCard QR (PNG / terminal) |
| `zbar` | repo (`extra`) | Decode QR from webcam/screenshot (`zbarimg`, `zbarcam`) to receive cards |
| `python-qrcode` | repo (`extra`) | Alternative QR generator |
| `libnfc` | repo (`extra`) | NFC reader access (ACR122U etc.) |
| `pcsclite`, `ccid`, `pcsc-tools` | repo (`extra`) | PC/SC stack for USB NFC readers |
| `python-nfcpy`, `python-ndeflib` | AUR | Write/read NDEF vCard records |
| OpenDrop | not packaged (verify); `pip` / upstream | AirDrop experiments only |

Verification links: <https://archlinux.org/packages/extra/x86_64/qrencode/>,
<https://archlinux.org/packages/extra/x86_64/zbar/>,
<https://archlinux.org/packages/extra/x86_64/libnfc/>,
<https://aur.archlinux.org/packages/python-nfcpy>,
<https://aur.archlinux.org/packages/python-ndeflib>.

The repo's shared `qr` helper (`lib/delight`) already renders QR codes, so a
module needs no new package for the core path.

## Hardware requirements

- QR path: a screen. Receiving by QR needs a webcam (optional).
- NFC path: a USB NFC reader/writer (e.g. ACS ACR122U, supported by
  `libnfc`; verify model) and NTAG213/215/216 stickers. Built-in laptop NFC
  is rare and usually unsupported on Linux (verify per laptop).
- AirDrop experiment: Wi-Fi chip supporting monitor mode + frame injection
  on 5 GHz for OWL (verify per chip). Not recommended for users.

## Legal, ToS and privacy

- No Apple account or service involved in the fallback; no ToS exposure.
  Do not call it "NameDrop" in UI (Apple trademark); use "Share my card".
- AirDrop RE (OpenDrop) is research software; AirDrop has had sender
  hash-leak issues ([Heinrich et al., USENIX Security 2021][heinrich21]).
  Don't ship it.
- A vCard is personal data. Store it only in local config, show exactly
  which fields are shared before displaying the QR, default to name + one
  contact method, and auto-hide the QR after 60 s. QR codes on screen can be
  photographed by anyone nearby.
- Incoming vCards are untrusted input: parse defensively, size-limit, never
  auto-import, never open embedded URLs automatically.

## Prior art

- Apple NameDrop guide: <https://support.apple.com/guide/iphone/namedrop-iphone-share-contact-info-iph1b6c664b7/ios>
- OpenDrop: <https://github.com/seemoo-lab/opendrop>
- OWL (Open Wireless Link, AWDL): <https://github.com/seemoo-lab/owl>
- Continuity BLE notes: <https://github.com/furiousMAC/continuity>
- Stute et al., USENIX Security 2019: <https://www.usenix.org/conference/usenixsecurity19/presentation/stute>
- Heinrich et al., AirDrop PSI, USENIX Security 2021: <https://www.usenix.org/conference/usenixsecurity21/presentation/heinrich>
- vCard 3.0, RFC 2426: <https://www.rfc-editor.org/rfc/rfc2426>
- NFC Forum NDEF / nfcpy: <https://github.com/nfcpy/nfcpy>

## Effort estimate

- QR + `.vcf` share-target integration + receive-with-confirmation: 0.5-1
  agent session (~1-2 human days).
- NFC write/emulate: +1 session, hardware-dependent, experimental.
- AirDrop/NameDrop interop: not estimated (no-go).
- Contract change first: `contact` is not in the fixed module id list
  (alternatively the `share` or `phone` track owner adds "Share my card").

## Risks

- **Expectation gap (medium).** Users expect tap-to-share with iPhones; QR
  is one more step. Clear copy: "Scan with your phone camera".
- **Data leak (low).** Over-sharing fields; mitigate with field picker and
  QR auto-hide.
- **NFC hardware variance (medium).** Readers/tags differ; iPhone handling of
  vCard NDEF needs verification.
- **Untrusted vCards (low).** Malformed input; parse with limits.

## `/goal` prompt for a future module

Prerequisite: a separate `contract-change` PR adding `contact` to the fixed
module id list in `docs/contracts.md` and to `ci/ownership.json`.

```text
/goal Build the Delight module "contact" in https://github.com/hiresello/omarchy-delight: a NameDrop-style "Share my card" that shows my vCard as a QR code, sends it as a .vcf through existing share targets, and safely receives incoming cards.

Read docs/contracts.md first; it wins over this prompt. Read research/namedrop/README.md for background and constraints (NameDrop interop itself is a no-go; do not attempt AirDrop/AWDL).

TRACK: id "contact". Branch: track/contact. Owned paths: modules/contact/** only. Scaffold with `bin/delight dev new-module contact`. Base on main, PR against main, iterate until CI (ci/local.sh) is green. If a shared file must change, open a SEPARATE PR labelled contract-change.

SCOPE
- modules/contact/{module.json,defaults.json,bin/delight-contact,plugin/,tests/,README.md}. No systemd unit needed for v1.
- Verbs: install, uninstall, enable, disable, toggle, status [--json], doctor, open, plus `card [--vcf|--qr PATH]` and `receive <file.vcf>`. Install/uninstall idempotent, recorded in ~/.local/state/omarchy-delight/contact/installed.json; everything honors DELIGHT_DRY_RUN=1.
- Packages via pkg_add only: qrencode (repo); zbar (repo) optional for scanning a card from webcam/screenshot.
- Card data lives in config.modules.contact (config_get/config_set only): name, tel, email, org, url, plus sharedFields (default name + tel). Build vCard 3.0 with CRLF and RFC 2426 escaping (see research/namedrop/spike/vcard-qr.sh). Never commit personal data.
- Status JSON via delight_status_write: needs-setup ("Add your name in Share my card") until a name is set; on otherwise. Actions: "Show QR" (open plugin), "Send card…" (calls `delight share-targets --json` and `delight send <target> <tmp>.vcf`; do not source other modules).
- Plugin delight.contact: field checklist, large QR from the shared qr helper, auto-hide after 60 s (defaults.json), "Send card…" list of share targets; only qml/Delight components/tokens. UI copy "Share my card", never "NameDrop".
- receive: validate size (<64 KiB) and BEGIN/END:VCARD, show a preview + confirm via notify/plugin, then save to ~/Contacts/<name>.vcf; never auto-import, never open URLs from the card.
- Tests (TAP, tests/*-test.sh): vCard escaping and N derivation, sharedFields filtering, status JSON schema-valid in each state, dry-run install/uninstall, receive rejects oversized/malformed files.

DO NOT TOUCH anything outside modules/contact/**. No omarchy-* commands or omarchy.* ids. NFC is out of scope for v1.
```

[opendrop]: https://github.com/seemoo-lab/opendrop
[owl]: https://github.com/seemoo-lab/owl
[apple-namedrop]: https://support.apple.com/guide/iphone/namedrop-iphone-share-contact-info-iph1b6c664b7/ios
[continuity]: https://github.com/furiousMAC/continuity
[stute19]: https://www.usenix.org/conference/usenixsecurity19/presentation/stute
[heinrich21]: https://www.usenix.org/conference/usenixsecurity21/presentation/heinrich
