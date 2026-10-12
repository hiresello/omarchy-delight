# Install

Omarchy Delight needs Omarchy 4 (Hyprland, systemd user session) and `jq`.

```bash
git clone https://github.com/hiresello/omarchy-delight ~/src/omarchy-delight
~/src/omarchy-delight/install.sh
```

`install.sh` runs as your user and never asks for sudo. It is safe to re-run:
a second run changes nothing. It:

- links the checkout to `~/.local/share/omarchy-delight` and puts `delight` in
  `~/.local/bin`;
- installs and enables the `delight.control-center` shell plugin;
- adds a **Delight** submenu to the Omarchy menu;
- adds one marked line to `~/.config/hypr/hyprland.lua`, sourcing the
  generated `~/.config/omarchy-delight/hypr.lua`;
- adds a theme hook so Delight panels follow `omarchy-theme-set`.

Preview every change first with `DELIGHT_DRY_RUN=1 ./install.sh`.

## Installing features

The core install adds no features. Install the ones you want:

```bash
delight list                 # every module and whether it is installed
delight share install        # may ask for sudo: packages and firewall rules only
delight share enable
```

Then toggle features from the Control Center
(`delight ui summon delight.control-center`, or **Delight → Control Center** in
the Omarchy menu) or with `delight <id> toggle`.

Modules install packages from the Arch repos (and the AUR for `camera`'s
DroidCam) and record what they installed, so uninstall removes only those.
Firewall rules are added to ufw only for private ranges (10/8, 172.16/12,
192.168/16) and, when present, `tailscale0`.

If a feature can't work on your hardware (no Bluetooth adapter, no camera
kernel module, …) its tile says **Unsupported** with the reason; nothing else
breaks.

## Updating

```bash
git -C ~/src/omarchy-delight pull
~/src/omarchy-delight/install.sh
delight refresh              # regenerate Hyprland, menu and hook files
```
