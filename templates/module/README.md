# Example module (template)

Scaffold a module with `delight dev new-module <id>`. It copies this directory to
`modules/<id>/` and renames `example` to the new id.

- `module.json` — manifest, validated by `schema/module.schema.json`.
- `defaults.json` — default values for this module's key in `config.json`.
- `bin/delight-<id>` — verb entry point. Defaults come from `lib/delight/module.sh`;
  define `module_<verb>` to override one.
- `systemd/` — unit files listed in `module.json` `units[]` (`delight-<id>[-*].service`,
  with `PartOf=delight.target` and `WantedBy=delight.target`).
- `hypr.lua` (optional) — loaded from the generated `~/.config/omarchy-delight/hypr.lua`.
- `tests/` (optional) — `*.sh` TAP tests run by `tests/run`.

See `docs/contracts.md` for the full contract.
