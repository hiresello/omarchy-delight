# Modules

One directory per feature module, created from the template with
`delight dev new-module <id>`. The ids are fixed and each has an owning track
(see `ci/ownership.json`):

| id | Feature |
|---|---|
| `share` | AirDrop-style sharing |
| `phone` | Phone integration and Universal Clipboard |
| `input` | Universal Control (shared keyboard and mouse) |
| `airplay` | AirPlay receiver |
| `sync` | File and settings sync |
| `camera` | Continuity Camera |
| `sidecar` | Sidecar (tablet as a second display) |
| `hotspot` | Instant Hotspot and proximity |

Modules talk to each other only through the JSON CLI contracts in
`docs/contracts.md`, never by sourcing each other's files.
