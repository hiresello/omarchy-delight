# Find My network participation (OpenHaystack / Macless-Haystack)

Research only. Nothing here is wired into `install.sh` or any module.

## Recommendation: GO, experimental and strictly opt-in

Build a narrowly scoped module that (a) advertises the laptop itself as an
OpenHaystack-style accessory and (b) shows its last reported location to the
owner. It must be off by default, never ask for or store Apple Account
credentials itself, and present the legal/ToS risk before enabling.

Not recommended (no-go): cloning official Apple device keys, tracking
anything the user does not own, bundling a shared Anisette server, or any
"works out of the box" flow that logs into Apple on the user's behalf.

Why go: the "locate this laptop" half is small and well understood (BLE
advertising of a rotating public key; any nearby iPhone relays an encrypted
report). The report-fetching half works on Linux without a Mac today via
FindMy.py / Macless-Haystack / findmylinux, but it depends on a reverse-engineered
Apple login and Anisette, which Apple can break at any time. That is
acceptable for an opt-in experimental feature and unacceptable for a default.

Biggest product caveat: the laptop is only findable while it is powered on,
the Bluetooth adapter is up and the advertiser is running. Unlike Apple
hardware there is no low-power "findable when off" mode, so this is weak
theft recovery (a thief closing the lid ends it) and better at "where did I
leave it" while it is awake.

## How it works

1. **Key generation.** A P-224 key pair is generated locally. The public key
   (28 bytes) is split across the BLE MAC address and the payload of an Apple
   "Offline Finding" advertisement (manufacturer data, company ID `0x004C`,
   type `0x12`). See [furiousMAC/continuity: Find My][cont-findmy].
2. **Advertising.** The laptop (or a cheap BLE tag) broadcasts that frame.
   Apple devices that see it encrypt their own GPS location to the public key
   and upload the report to Apple. Apple devices do this without user
   interaction; it is the "crowd" part of the network.
3. **Fetching.** The owner queries Apple's servers by the SHA-256 hash of the
   public key, downloads the encrypted reports and decrypts them locally with
   the private key. Apple cannot read the location; Apple does see which
   account is asking for which key hash, and when.
4. **Authentication.** Apple only answers that query for an authenticated
   Apple Account. Without a Mac this needs:
   - an Apple Account with 2FA (Macless-Haystack documents SMS 2FA; FindMy.py
     supports SMS and trusted-device 2FA), and
   - **Anisette** data (machine provisioning headers normally produced by
     Apple's own software). Linux projects get it from
     [Dadoum/anisette-v3-server][anisette] (runs Apple's Android
     CoreADI library) either locally or from a public server.
   Public Anisette servers see the account's provisioning traffic; the module
   must default to a local server.

Key rotation: official AirTags rotate keys every 15 minutes (derived keys).
OpenHaystack firmware commonly uses a static key or a small key list, which is
easier to track by third parties (see Privacy).

## Current upstream state (checked 2026-10)

| Project | State | Notes |
| --- | --- | --- |
| [seemoo-lab/openhaystack][openhaystack] | Original research project; macOS 11+ app; downloads reports via an Apple Mail plugin (private API). README marks it experimental and unaffiliated with Apple. | Reference for firmware (ESP32, nRF51/52, Linux HCI) and the protocol, not usable on Linux for fetching. |
| [dchristl/macless-haystack][macless] | Active. Fetches reports with no Mac via Docker: an Anisette container + an "endpoint" container, Apple Account + SMS 2FA entered interactively; web/Flutter frontend. AGPL-3.0, "for research purposes". | Supports ESP32, nRF5x, ST17H66 and other OpenHaystack-compatible tags. |
| [malmeloo/FindMy.py][findmypy] | Active (release `v0.10.2`, commits through 2026-09). Python library: Apple login (SMS / trusted-device 2FA), Anisette, fetch and decrypt reports for official accessories (with their keys) and custom OpenHaystack keys, sync and async APIs. On PyPI as `FindMy`. | Best building block for a Delight module. |
| [biemster/FindMy][biemster] | Scripts: generate keys, `request_reports.py`, uses `anisette-v3-server`. | Minimal prior art; good for reading. |
| [Dadoum/anisette-v3-server][anisette] | Active (commits through 2026-09). Lightweight Anisette v3 server (D language), Docker or native. | Packaged in AUR as `findmylinux-anisette`. |
| [cmdada/findmylinux][findmylinux] | New (AUR `0.1.1-1`). Advertises *this laptop* on Find My from BlueZ (extended advertising where available), needs `CAP_NET_ADMIN`/`CAP_NET_RAW`, GTK4/libadwaita map UI, systemd service, local Anisette at `http://127.0.0.1:6969`, default report fetch interval 600 s. | Closest prior art to the module; very young, low adoption, audit before depending on it. |

## What works on Arch today

Verified on archlinux.org / aur.archlinux.org (2026-10). Repo = official
Arch repositories (`core`/`extra`).

| Package | Source | Purpose |
| --- | --- | --- |
| `bluez`, `bluez-utils` | repo (`extra`) | BLE adapter, `bluetoothctl`, `btmgmt` for advertising |
| `python-cryptography` | repo (`extra`) | P-224 keys, ECDH/AES-GCM report decryption |
| `python-requests` | repo (`extra`) | HTTP for report fetch (used by findmylinux) |
| `python-gobject`, `gtk4`, `libadwaita`, `libshumate` | repo (`extra`) | findmylinux GUI (not needed by a Delight module, which uses its own plugin) |
| `geoclue`, `polkit` | repo (`extra`) | findmylinux dependencies |
| `docker`, `docker-compose` | repo (`extra`) | Macless-Haystack / containerised Anisette |
| `findmylinux` | AUR (`0.1.1-1`) | Laptop advertiser + fetcher |
| `findmylinux-anisette` | AUR (`2.2.2-1`, builds `Dadoum/anisette-v3-server`) | Local Anisette server |
| FindMy.py | not packaged for Arch (verify: no `python-findmy` in repo or AUR at time of writing); PyPI `FindMy` `0.10.2` | Fetch/decrypt library; would need a venv under `~/.local/share/omarchy-delight/` or a new AUR package |
| Macless-Haystack | not packaged (verify); upstream Docker images | Full no-Mac stack |

Verification links: <https://archlinux.org/packages/?q=bluez>,
<https://archlinux.org/packages/extra/x86_64/python-cryptography/>,
<https://archlinux.org/packages/extra/x86_64/docker/>,
<https://aur.archlinux.org/packages/findmylinux>,
<https://aur.archlinux.org/packages/findmylinux-anisette>,
<https://pypi.org/project/FindMy/>.

## Hardware requirements

- **Laptop as accessory:** any BlueZ-supported BLE adapter that allows a
  random static address and legacy advertising (Bluetooth 4.0+). Extended
  advertising (5.0) is nice to have. Intel AX2xx/BE2xx and most Realtek
  combos should work (verify per adapter; some firmware refuses to change the
  advertising address while connected to audio devices).
- **Cheap tag:** ESP32 (~£5), nRF51822/nRF52832 beacons (~£5-10), ST17H66
  tags (~£3) flashed with OpenHaystack/Macless-Haystack firmware. Flashing
  needs a USB-UART or SWD programmer (verify per board).
- **Reports:** nothing local; requires Apple devices physically near the
  laptop/tag. Coverage is good in cities, poor rurally.
- **Account:** an Apple Account with 2FA (a phone number for SMS). A Mac is
  *not* required.

## Legal, ToS and privacy

- **Apple ToS.** The [iCloud Terms][icloud-terms] require keeping account
  credentials confidential and forbid interfering with or accessing the
  service by unauthorised means. Using a reverse-engineered client and
  Anisette to query Find My is at best unsanctioned. Plausible consequences:
  account lock or ban. Recommend a dedicated, non-primary Apple Account and say
  so in the UI. Not legal advice; verify with counsel before any distribution
  beyond hobby use.
- **Apple MFi.** Apple's official route for Find My accessories is the
  [Find My network accessory program][apple-findmy] (MFi enrolment, specs
  under NDA). OpenHaystack is not that; nothing here may be marketed as
  "Works with Apple Find My".
- **Credentials.** No Apple credentials, session tokens, Anisette state or
  private keys may ever enter the repo. A module must keep keys under
  `~/.local/state/omarchy-delight/<id>/` with `0600` permissions, and let the
  login happen in the upstream tool's own interactive flow.
- **Licences.** Macless-Haystack is AGPL-3.0; do not vendor its code into
  Delight. FindMy.py and findmylinux: check licences before packaging (verify).
- **Stalking / UK and EU law.** A tag that does not rotate keys and does not
  play an anti-stalking alert can be used to track people covertly. Apple and
  Google's unwanted-tracking alerts do not reliably flag OpenHaystack tags
  ([Heinrich et al., PETS 2021][popets21], and later work). The IETF
  [DULT draft][dult] describes expected anti-stalking behaviour. The module
  must only manage devices the user owns, must rotate keys, and should
  document that misuse is a criminal offence in many jurisdictions (e.g.
  Protection from Harassment Act 1997 in England & Wales).
- **Data protection.** Location history of the owner is personal data. Store
  locally only, cap retention (e.g. 7 days by default), never sync to a
  third party. Apple still learns that the account polls specific key hashes.

## Prior art

- OpenHaystack: <https://github.com/seemoo-lab/openhaystack>
- Macless-Haystack: <https://github.com/dchristl/macless-haystack>
- FindMy.py: <https://github.com/malmeloo/FindMy.py>
- biemster/FindMy: <https://github.com/biemster/FindMy>
- anisette-v3-server: <https://github.com/Dadoum/anisette-v3-server>
- findmylinux: <https://github.com/cmdada/findmylinux>
- Continuity protocol notes: <https://github.com/furiousMAC/continuity>
- Heinrich et al., "Who Can Find My Devices?", PETS 2021: <https://petsymposium.org/popets/2021/popets-2021-0045.pdf>
- Heinrich et al., "OpenHaystack/Find My", USENIX Security 2021: <https://www.usenix.org/conference/usenixsecurity21/presentation/heinrich>
- IETF DULT accessory protocol draft: <https://datatracker.ietf.org/doc/draft-ietf-dult-accessory-protocol/>

## Effort estimate

- Laptop advertiser + key management + status tile, wrapping `btmgmt`: 1 agent
  session (~2-3 human days).
- Report fetching via FindMy.py in a private venv + local Anisette (Docker or
  `findmylinux-anisette`), map/last-seen popover plugin: 1-2 agent sessions.
- Tag support (flashing guides, multiple keys, rotation): +1 session; leave
  for later.
- Contract change first: `findmy` is not in the fixed module id list.

## Risks

- **Apple breakage (high).** Login, Anisette or report endpoints can change
  without notice; the feature can die overnight. Status must degrade to
  `error` with a clear reason.
- **Account risk (medium).** Lock-out of the user's Apple Account; mitigate
  with the dedicated-account warning.
- **Advertising conflicts (medium).** BLE advertising while BlueZ is also
  used for AirPods/phone may fail on some adapters (verify); MAC rotation can
  disturb other BLE sessions.
- **Weak theft recovery (product).** Off/asleep = not findable; set
  expectations in the UI.
- **Dependency maturity (medium).** `findmylinux` is new with one maintainer;
  FindMy.py is not in Arch repos. Prefer FindMy.py + own minimal advertiser
  over a hard dependency on findmylinux.
- **Privacy/abuse (medium).** Static-key tags enable stalking; enforce key
  rotation and "own devices only" copy.

## `/goal` prompt for a future module

Prerequisite: a separate `contract-change` PR adding `findmy` to the fixed
module id list in `docs/contracts.md` and to `ci/ownership.json`.

```text
/goal Build the experimental, opt-in Delight module "findmy" in https://github.com/hiresello/omarchy-delight: make this laptop findable on Apple's Find My network and show its last reported location, without a Mac.

Read docs/contracts.md first; it wins over this prompt. Read research/find-my/README.md for background and constraints.

TRACK: id "findmy". Branch: track/findmy. Owned paths: modules/findmy/** only. Scaffold with `bin/delight dev new-module findmy`. Base on main, PR against main, iterate until CI (ci/local.sh) is green. If a shared file must change, open a SEPARATE PR labelled contract-change.

SCOPE
- modules/findmy/{module.json,defaults.json,bin/delight-findmy,systemd/,plugin/,tests/,README.md}.
- Verbs: install, uninstall, enable, disable, toggle, status [--json], doctor, plus `open` (summons the plugin). Install/uninstall idempotent and recorded in ~/.local/state/omarchy-delight/findmy/installed.json. Everything honors DELIGHT_DRY_RUN=1.
- Packages via pkg_add only: bluez, bluez-utils, python-cryptography (repo); findmylinux-anisette (AUR) for a LOCAL Anisette server on 127.0.0.1. FindMy.py from PyPI into a private venv under ~/.local/share/omarchy-delight/findmy/venv (record it for uninstall). No public Anisette servers by default.
- Keys: generate a P-224 key list locally into ~/.local/state/omarchy-delight/findmy/keys (0600); rotate the advertised key (default every 15 min). Never commit or log keys.
- Advertising: unit delight-findmy-advertise.service (PartOf=delight.target, WantedBy=delight.target) that emits the Offline Finding frame (company 0x004C, type 0x12) via btmgmt/BlueZ; doctor checks adapter support (hw_* helpers) and returns 2 with a reason if unsupported.
- Reports: unit delight-findmy-fetch.service + .timer (default 15 min) calling FindMy.py with the user's own session; store decrypted reports locally with 7-day retention (defaults.json).
- Apple login: never prompt for or store the password in Delight. `delight-findmy pair` opens a terminal running FindMy.py's interactive login; until a session exists, status state is needs-setup with reason "Sign in with a dedicated Apple Account".
- Status JSON via delight_status_write: off by default; on shows "Findable" + last report age as subtitle; error with a human reason when Anisette/login/fetch fails. Actions: toggle, "Show location" (open plugin), "Sign in".
- Plugin delight.findmy: last-seen list (time, accuracy, coordinates, "open in browser map" link), using only qml/Delight components/tokens. No embedded map tiles from third parties by default.
- First enable must show a notify + plugin consent page: unofficial, may violate Apple ToS, use a dedicated account, only for devices you own, laptop is not findable when off.
- Tests (TAP, tests/*-test.sh): dry-run install/uninstall records, status JSON validates against schema/status.schema.json in every state, key rotation selection, retention pruning, doctor exit codes with stubbed btmgmt.

DO NOT TOUCH anything outside modules/findmy/**. No Apple credentials, tokens, Anisette state or keys in the repo. No DIY tag flashing in v1. No omarchy-* commands or omarchy.* ids.
```

[cont-findmy]: https://github.com/furiousMAC/continuity/blob/master/messages/findmy.md
[anisette]: https://github.com/Dadoum/anisette-v3-server
[openhaystack]: https://github.com/seemoo-lab/openhaystack
[macless]: https://github.com/dchristl/macless-haystack
[findmypy]: https://github.com/malmeloo/FindMy.py
[biemster]: https://github.com/biemster/FindMy
[findmylinux]: https://github.com/cmdada/findmylinux
[icloud-terms]: https://www.apple.com/legal/internet-services/icloud/en/terms.html
[apple-findmy]: https://developer.apple.com/find-my/
[popets21]: https://petsymposium.org/popets/2021/popets-2021-0045.pdf
[dult]: https://datatracker.ietf.org/doc/draft-ietf-dult-accessory-protocol/
