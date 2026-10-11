# Testing

```bash
tests/run                      # every test file (TAP), sandboxed, no root needed
tests/run tests/unit/lib.sh    # one file
ci/local.sh                    # the whole CI job in archlinux:latest (Docker)
```

Tests run against a copy of the repo with a throwaway `$HOME` and
`$XDG_RUNTIME_DIR`. `tests/stubs/` shadows `systemctl`, `sudo`, `pacman`,
`ufw`, `omarchy`, `omarchy-shell` and friends; each stub logs its argv to
`$DELIGHT_STUB_LOG` and keeps just enough state (enabled units and plugins,
"installed" packages) for idempotence checks. Nothing touches the real system.

| Path | What it covers |
|---|---|
| `tests/unit/lib.sh` | `lib/delight` helpers: config, state, packages, firewall, units, status, marked blocks, dry-run |
| `tests/unit/ownership.sh` | `ci/check-ownership.sh` |
| `tests/contract/modules.sh` | Runs `tests/contract/check-module` on every module, on `templates/module` copied unchanged to `modules/example`, and on a `delight dev new-module` scaffold |
| `tests/install/install.sh` | `install.sh` / `uninstall.sh`: dry-run, idempotence, touchpoints, byte-for-byte restore |
| `modules/<id>/tests/*.sh` | A module's own tests (owned by its track) |

`tests/lib/tap.sh` provides `ok`, `not_ok`, `is`, `sandbox`, `repo_copy`,
`tree_hash` and `schema_valid`; finish each file with `done_testing`.

## The module contract test

`tests/contract/check-module <repo> <id>` checks that a module:

- has a schema-valid `module.json` whose `id` matches its directory, an
  executable `bin/delight-<id>`, and units tied to `delight.target`;
- does not reference another module's files;
- answers `status --json` with schema-valid JSON and exit 0 before and after install;
- can dry-run `install` without touching `$HOME`;
- installs idempotently, writes its status file, and moves `on`/`off` through
  `enable`, `toggle` and `disable` (unless it reports `unsupported`);
- exits `0`–`3` from `doctor`, and returns schema-valid provider output;
- uninstalls idempotently, leaving no state, status file or config key.

A new module passes this unchanged when scaffolded from the template.

## CI

`.github/workflows/ci.yml` runs in `archlinux:latest`:

1. `ci/lint-shell.sh` — shellcheck and `shfmt -i 2 -ci -bn` on every Bash file.
2. `ci/lint-qml.sh` — `qmllint` on `qml/Delight` and each staged plugin, with
   `qs.*` resolved against a shallow clone of `omacom/omarchy`.
3. `ci/validate-json.py` — every schema against its valid/invalid fixtures,
   every `module.json`, and every JSON file parses. (Python is CI-only.)
4. `ci/validate-plugins.sh` — Omarchy's own `bin/omarchy-plugin-validate` on
   each staged plugin.
5. `tests/run`, as an unprivileged user.
6. `ci/check-ownership.sh` on pull requests (see `CONTRIBUTING.md`).

Hardware-level testing (Bluetooth, Wi-Fi, portals) is the VM track's job
(`vm/`, `docs/vm.md`).

## Manual check on Omarchy 4

```bash
cp ~/.config/hypr/hyprland.lua /tmp/before.lua
./install.sh
omarchy plugin list | grep delight.control-center   # enabled
delight status --json                                # []
hyprctl reload                                       # no config errors
./uninstall.sh && cmp ~/.config/hypr/hyprland.lua /tmp/before.lua
```
