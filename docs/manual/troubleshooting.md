# Troubleshooting

Start with:

```bash
delight status            # one line per installed module: id, state, subtitle (reason)
delight doctor            # every installed module's checks
delight <id> doctor       # one module
```

Each `doctor` line is `ok`, or explains what's wrong and what to do. The exit
code says what kind of problem it is:

| Exit | Meaning | What to do |
| --- | --- | --- |
| 0 | Everything is fine | — |
| 1 | Fixable by Delight | Run `delight <id> install` again, then `delight <id> enable` |
| 2 | Unsupported hardware or compositor | Nothing to fix; the tile says **Unsupported** with the reason |
| 3 | Needs you | Do the step it prints (pair a phone, plug in a device, approve a prompt) |

## Common problems

- **A tile is missing from the Control Center.** Only installed modules have
  tiles: check `delight list`. If it's installed, `delight refresh`, then
  reopen the panel.
- **The Control Center doesn't open.** `omarchy plugin list` should show
  `delight.control-center` as enabled. Re-run `install.sh`.
- **A tile says Error.** Its subtitle has the reason. `delight <id> status --json`
  shows the full status; the module's logs are in
  `journalctl --user -u 'delight-<id>*'`.
- **Phones aren't found** (share, phone, sync, camera, AirPlay). Both devices
  must be on the same private network; guest and corporate Wi-Fi often block
  devices from seeing each other. Check the firewall rules with
  `sudo ufw status | grep omarchy-delight`.
- **Hyprland config errors after installing.** `hyprctl configerrors`. Delight's
  only change to your config is one marked line in `hyprland.lua`; uninstall
  removes it.
- **Something is left over after uninstall.** Please open an issue with
  `pacman -Qe`, `sudo ufw status verbose` and the output of `delight doctor`
  from before uninstalling.

Each feature's README has a module-specific troubleshooting section: see the
links on the [feature pages](README.md).
