# Contracts

These are the interfaces between Delight's core and its modules, and between
modules. Feature tracks build against them in parallel, so changing one is a
**contract change**: it needs the `contract-change` PR label and an update to
this file, the schemas in `schema/`, and the contract tests in `tests/contract/`.

## Names and paths

| What | Where |
|---|---|
| Checkout (symlink to the repo) | `~/.local/share/omarchy-delight` |
| CLI | `~/.local/bin/delight` → `bin/delight` |
| Config | `~/.config/omarchy-delight/config.json` (`schema/config.schema.json`) |
| Generated Hyprland config | `~/.config/omarchy-delight/hypr.lua` |
| Install records | `~/.local/state/omarchy-delight/<id>/installed.json` |
| Live status | `$XDG_RUNTIME_DIR/omarchy-delight/status/<id>.json` |
| Plugins | `~/.config/omarchy/plugins/delight.*` (copies, never symlinks) |
| systemd | `delight.target` (wanted by `graphical-session.target`); module units `delight-<id>[-*].service` |
| Firewall rule comment | `omarchy-delight:<id>` |

Delight never writes to `/usr/share/omarchy`, never uses the `omarchy-*`
command prefix or the `omarchy.*` plugin namespace, and `install.sh` never
needs sudo. Module installs may call `sudo` through `delight_pkg_add` and
`delight_ufw_allow` only.

Module ids are fixed: `share phone input airplay sync camera sidecar hotspot`.

## Module layout

```
modules/<id>/
  module.json          manifest (schema/module.schema.json)
  defaults.json        default values for config.modules.<id>
  bin/delight-<id>     verb entry point
  systemd/             units listed in module.json units[]
  hypr.lua             optional; loaded from the generated hypr.lua
  plugin/              optional Omarchy shell plugin (manifest id delight.<something>)
  tests/*.sh           optional TAP tests, run by tests/run
```

### module.json

| Field | Meaning |
|---|---|
| `schema` | Always `1` |
| `id`, `name`, `icon`, `description` | Identity; `id` equals the directory name |
| `packages.repo[]`, `packages.aur[]` | Installed by the default `install`; only packages Delight added are removed |
| `units[]` | `delight-<id>[-*].{service,timer,socket,path}`; each must have `PartOf=delight.target` and `WantedBy=delight.target` |
| `firewall[]` | `{proto: tcp\|udp, ports: "N" \| "A:B"}`; opened to RFC1918 ranges and `tailscale0` only |
| `capabilities[]` | Hardware/session needs, for docs and `doctor` (`bluetooth`, `wifi-monitor`, `portal`, …) |
| `provides.shareTargets`, `provides.devices` | Whether the module answers `share-targets --json` / `devices --json` |
| `plugin` | Path of a plugin directory inside the module, or `null` |
| `menu[]` | `{id, label, icon?, action}`; becomes `delight.<id>.<item>` in the Omarchy menu |
| `hooks[]` | Optional; `theme-set` makes `delight hook theme-set` call `delight-<id> theme-set <theme>` |

## Verbs

Every `bin/delight-<id>` supports:

| Verb | Contract |
|---|---|
| `install` | Idempotent. Records everything it adds via the `delight_*` helpers. Honours `DELIGHT_DRY_RUN=1`. |
| `uninstall` | Reverses exactly what `install` recorded; idempotent; a no-op when not installed. |
| `enable` / `disable` | Set `config.modules.<id>.enabled`, start/stop units, rewrite the status file. After `enable` the state is `on`, or `needs-setup` when the module is enabled but waits on the user (e.g. connecting a phone). |
| `toggle` | `enable` when disabled, otherwise `disable`. |
| `status [--json]` | `--json` prints one status object and **always exits 0**, including when unsupported. |
| `doctor` | Human-readable diagnosis. Exit `0` ok, `1` fixable, `2` unsupported hardware/compositor, `3` needs user action. |

Optional: `pair`, `open`, `share-targets --json`, `send <target> <paths...>`,
`devices --json`, `theme-set <theme>`. Unknown verbs exit non-zero.

`lib/delight/module.sh` implements every required verb from `module.json`.
A module overrides one by defining `module_<verb>` before calling
`delight_module_main "$@"`; the template shows the pattern.

## Status JSON

`schema/status.schema.json`. Written to the runtime status directory on every
change (`delight_status_write`), and printed by `status --json`.

```json
{"schema":1,"id":"airplay","state":"on","title":"AirPlay","subtitle":"Receiving as Desk",
 "icon":"󰑈","toggle":true,"actions":[{"label":"Settings","command":["delight","airplay","open"]}],
 "devices":[],"reason":null,"updated":"2026-10-11T12:00:00Z"}
```

`state` is one of `on off busy needs-setup unsupported error`; `reason` is
required for `unsupported` and `error`. The Control Center draws one tile per
file: clicking runs `delight <id> toggle` (when `toggle` is true), the chevron
runs `actions[0].command` or `delight <id> open`.

## Providers

`share-targets --json`, `schema/share-target.schema.json`:

```json
[{"id":"phone:pixel-8","label":"Pixel 8","icon":"","kind":"phone"}]
```

`devices --json`, `schema/device.schema.json`:

```json
[{"id":"pixel-8","name":"Pixel 8","kind":"phone","transport":"kdeconnect","connected":true,"rssi":-55,"mac":"AA:BB:CC:DD:EE:FF"}]
```

`delight share-targets --json` and `delight devices --json` merge the output
of every installed module whose manifest sets the matching `provides` flag,
adding `"module": "<id>"` to each entry. A module that wants another module's
targets calls these commands; it never sources another module's files.

## Config

`config.json` is `{"schema":1,"modules":{"<id>":{...}}}`. A module reads and
writes only its own key, through `delight_config_get/set` (or
`delight config get|set <id>.<key>`). Unset keys fall back to
`modules/<id>/defaults.json`. Writes are serialized with `flock`.

## Shared library

Source `lib/delight/delight.sh`. Every side-effecting helper prints
`DRY: <action>` instead of acting when `DELIGHT_DRY_RUN=1`.

| Helper | Purpose |
|---|---|
| `delight_log`, `delight_warn`, `delight_die <msg> [code]` | Messages to stderr |
| `delight_pkg_add <id> repo\|aur <pkgs...>`, `delight_pkg_remove <id>` | Packages via `omarchy-pkg-add` / `omarchy-pkg-aur-add`, falling back to pacman / yay |
| `delight_ufw_allow <id> <proto> <ports>`, `delight_ufw_revoke <id>` | Private-LAN firewall rules |
| `delight_unit_install <id> <file>`, `delight_unit_dropin <id> <unit> <conf>`, `delight_unit_remove <id>` | systemd user units |
| `delight_file_install <id> <src> <dest>` | Any other file outside the repo |
| `delight_status_json …`, `delight_status_write <id> <json>` | Status |
| `delight_config_get <id> <key>`, `delight_config_set <id> <key> <value>` | Config |
| `delight_notify <id> <title> <body>` | Notification via `omarchy-notification-send` |
| `delight_has_cmd`, `delight_hw_bluetooth`, `delight_hw_wifi_monitor`, `delight_hw_kmod_loadable <mod>`, `delight_hw_hyprland`, `delight_hw_portal <iface>` | Capability checks |
| `delight_qr <text> [out.png]` | QR code via `qrencode` |

## User files Delight touches

All generated from the installed modules by `delight sync` (run by
`install.sh` and every module `install`/`uninstall`):

- `~/.config/hypr/hyprland.lua` — a marked block with one line,
  `pcall(dofile, os.getenv("HOME") .. "/.config/omarchy-delight/hypr.lua")`.
- `~/.config/omarchy/extensions/omarchy-menu.jsonc` — a marked block with the
  `delight` submenu and each module's `menu[]`.
- `~/.config/omarchy/hooks/theme-set.d/50-omarchy-delight`.

Markers are `>>> omarchy-delight >>>` / `<<< omarchy-delight <<<`. The first
insert snapshots the file; `uninstall.sh` restores the snapshot byte-for-byte
when nothing else changed, and otherwise removes only the marked lines.
