# Uninstall

```bash
~/src/omarchy-delight/uninstall.sh
```

This uninstalls every module, then removes every file Delight added and
restores the files it touched byte-for-byte: `~/.config/hypr/hyprland.lua`,
the Omarchy menu file and the Control Center plugin. If you edited
`hyprland.lua` after installing, your edits stay; only the Delight block goes.

Each module's `uninstall` removes:

- the packages it installed (packages you already had stay);
- its ufw rules (all are tagged `omarchy-delight:<id>`);
- its systemd user units, Hyprland snippet, plugin and runtime files.

To remove a single feature: `delight <id> uninstall`.

Your data stays: `~/Sync`, received files, Syncthing and KDE Connect pairings.

## Verifying a clean uninstall

The VM end-to-end test (`tests/e2e/vm-continuity.sh`) checks this
automatically. To check by hand, take these before installing and compare
after uninstalling:

```bash
pacman -Qe > /tmp/before.pacman
sudo ufw status verbose > /tmp/before.ufw
(cd ~/.config/hypr && find . -type f -print0 | sort -z | xargs -0 sha256sum) > /tmp/before.hypr
```
