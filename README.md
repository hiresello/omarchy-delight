# Omarchy Delight

An open-source theme and tool suite that aims to give [Omarchy](https://github.com/omacom/omarchy)
macOS-level design and UX. The first focus is Apple Continuity-style features:
AirDrop-style sharing, Universal Clipboard, Universal Control, an AirPlay
receiver, sync, Continuity Camera, Sidecar, Instant Hotspot and proximity.

Everything lives in one theme-aware **Control Center**, degrades gracefully
on hardware that can't do a feature, only opens ports to your private LAN,
and uninstalls cleanly.

> **Status:** foundation only (Phase 0). The CLI, contracts, installer,
> module template and a minimal Control Center exist; no feature module has
> landed yet.

## Install

On Omarchy 4:

```bash
git clone https://github.com/hiresello/omarchy-delight ~/src/omarchy-delight
~/src/omarchy-delight/install.sh
```

`install.sh` runs as your user, never needs sudo, and is safe to re-run. It
links the checkout to `~/.local/share/omarchy-delight`, adds `delight` to
`~/.local/bin`, installs and enables the `delight.control-center` shell
plugin, adds a `Delight` submenu to the Omarchy menu, and adds one marked
line to `~/.config/hypr/hyprland.lua`. Preview everything with
`DELIGHT_DRY_RUN=1 ./install.sh`.

`./uninstall.sh` removes every module and every file Delight added, and
restores the files it touched byte-for-byte.

## Use

```bash
delight list                          # available modules
delight <id> install                  # install a module (may ask for sudo for packages/firewall)
delight <id> toggle                   # or click its tile in the Control Center
delight status --json
delight doctor
delight ui summon delight.control-center
```

## Layout

| Path | |
|---|---|
| `bin/delight` | Dispatcher CLI |
| `lib/delight/` | Shared Bash helpers |
| `schema/` | JSON Schemas and fixtures |
| `modules/<id>/` | Feature modules |
| `templates/module/` | Module template (`delight dev new-module <id>`) |
| `qml/Delight/` | Shared QML tokens and components |
| `plugins/control-center/` | The Control Center shell plugin |
| `tests/`, `ci/` | Tests and CI scripts |
| `vm/`, `research/` | VM harness and research notes (separate tracks) |

Read [`docs/contracts.md`](docs/contracts.md) before writing a module, and
[`docs/testing.md`](docs/testing.md) for how to test one.
[`CONTRIBUTING.md`](CONTRIBUTING.md) covers branches and ownership.
