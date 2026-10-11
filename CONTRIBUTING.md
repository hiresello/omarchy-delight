# Contributing

## Tracks and ownership

Work happens on parallel tracks, each owning a set of paths
(`ci/ownership.json`):

| Track | Owns |
|---|---|
| `share` `phone` `input` `airplay` `sync` `camera` `sidecar` `hotspot` | `modules/<id>/**` |
| `ui` | `plugins/control-center/**`, `qml/Delight/**`, `docs/design.md` |
| `vm` | `vm/**`, `docs/vm.md`, `.github/workflows/vm.yml` |
| `research` | `research/**` |
| `integration` | `tests/e2e/**`, `docs/manual/**`, `CHANGELOG.md` |

A branch named `track/<id>` may only change its own paths; CI fails
otherwise. Anything shared — `bin/`, `lib/`, `schema/`, `templates/`,
`tests/lib`, `tests/contract`, `install.sh`, `uninstall.sh`, `ci/`, `docs/contracts.md` —
is a **contract change**: open it as its own PR with the `contract-change`
label, update `docs/contracts.md`, the schemas and the contract tests
together, and keep it small so the other tracks can rebase onto it quickly.

## Rules

- Runtime code is Bash, `jq` and QML. Python is for CI only.
- Commands are `delight …`; plugin ids are `delight.*`. Never `omarchy-*` or `omarchy.*`.
- Never write to `/usr/share/omarchy`. Extend Omarchy through its user config,
  hooks, menu extensions and plugin directory only.
- Every side effect goes through a `delight_*` helper so it is recorded for
  uninstall and honours `DELIGHT_DRY_RUN=1`.
- Modules don't source or reference each other's files; use the JSON CLI contracts.
- Firewall rules go through `delight_ufw_allow` (private ranges and `tailscale0` only).
- `status --json` always exits 0. Unsupported hardware is a state, not a crash.

## Before you push

```bash
tests/run
ci/local.sh      # full CI in archlinux:latest, needs Docker
```

Shell is formatted with `shfmt -i 2 -ci -bn` and must be shellcheck-clean.
