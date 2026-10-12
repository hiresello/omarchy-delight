# VM test harness

`vm/` boots a disposable, freshly installed Omarchy in QEMU/KVM so module
authors can prove their `[VM]` acceptance criteria on the real desktop:
Hyprland, the Omarchy shell (Quickshell), systemd user units and `omarchy`
itself, with nothing mocked.

```bash
vm/up && vm/install-delight main && vm/run-all
```

## Why this approach

Two options were on the table:

1. **QEMU + the official ISO + an unattended install.** The ISO
   (`https://iso.omarchy.org/omarchy-<version>.iso`, with `.sha256` and `.sig`
   beside it) installs without a keyboard when a `cidata` volume carries
   `user_configuration.json` and `user_credentials.json` (manual, "Unattended
   installs"). It works, but every fresh machine costs a full install: 6 GB
   download, a UEFI firmware boot, archinstall and a reboot, roughly 10–20
   minutes, and we would own the credentials, partitioning and firstboot
   plumbing.
2. **Reuse omarchy-iso's VM tooling.** The nightly pipeline of
   [omacom/omarchy-iso](https://github.com/omacom/omarchy-iso) already does that
   unattended install, runs Omarchy's acceptance checks (`omarchy-iso-test`,
   `test/vm-image/vm-verify`), then seals the result and publishes it as a
   QCOW2 image with its kernel, initrd and command line unpacked beside it.
   Its `test/vm-image/vm-boot` boots that image directly (no firmware or
   bootloader), injects a fresh SSH key through a systemd credential and
   reaches the desktop in about 15 seconds.

The harness takes option 2: it pins a sealed image of the latest stable release
in `vm/image.env` and boots it the way `vm-boot` does. That is simpler (no
installer in our tree), more robust (the image has passed Omarchy's own
acceptance suite) and much faster. On top of `vm-boot`'s throwaway runs, the
harness keeps a persistent machine with QEMU internal snapshots (RAM and disk),
so `fresh` restores in seconds.

Image locations, all served by Omarchy and verified by `vm/up`:

| What | Where |
| --- | --- |
| Latest stable metadata (ISO and VM, with sha256) | `https://nightly.omarchy.org/stable/latest.json` (`edge/latest.json` for edge) |
| Sealed VM image | `vm.url` in that file, e.g. `https://nightly.omarchy.org/stable/4.0.4/440/omarchy-4.0.4.qcow2` |
| Kernel, initrd, cmdline, `SHA256SUMS` | `vm.unpacked`, e.g. `https://nightly.omarchy.org/stable/4.0.4/440/unpacked/` |
| Release ISO | `https://iso.omarchy.org/omarchy-4.0.4.iso` (sha256 `ddeded27…f92d`, `.sig` beside it) |

To move to a new release, copy `version`, `vm.url`, `vm.sha256` and
`vm.unpacked` from `latest.json` and the three hashes from `SHA256SUMS` into
`vm/image.env`. `DELIGHT_VM_IMAGE=latest vm/up` tries the newest stable image
without editing anything (verified against the hashes the server publishes).

## Requirements

- Linux x86_64 with KVM: `/dev/kvm` readable and writable by you (be in the
  `kvm` group, or add a udev rule such as
  `KERNEL=="kvm", GROUP="kvm", MODE="0666"`).
- `qemu-system-x86_64` and `qemu-img` (QEMU 6.2 or newer), `ssh`,
  `ssh-keygen`, `curl`, `jq`. On Arch: `pacman -S qemu-base openssh jq`; on
  Debian/Ubuntu: `apt install qemu-system-x86 qemu-utils openssh-client jq`.
- About 4 CPUs and 5 GB of free RAM for the guest (`DELIGHT_VM_SMP`,
  `DELIGHT_VM_MEM`), and 15 GB of disk: 4.5 GB for the image, the rest for the
  machine's overlay and snapshots.

The guest is the stock image: user `omarchy`, password `omarchy`, Omarchy at
`/usr/share/omarchy`, `grim`, `hyprctl`, `jq` and `git` installed. While
preparing `fresh`, `vm/up` gives that user passwordless sudo, syncs the pacman
databases (the image ships without them) and keeps the screen awake.

## Commands

| Command | Does |
| --- | --- |
| `vm/up` | Restore the `fresh` snapshot, booting the VM if it is off. The first run downloads and verifies the image (one time, ~2 min on a fast link), boots it and saves `fresh`. `--snapshot NAME` restores another snapshot, `--keep` just makes sure it runs, `--new` rebuilds the machine. |
| `vm/install-delight <ref\|path>` | Install Delight in the guest from a git ref (fetched from `origin`, else resolved locally) or a local checkout (uncommitted files included). Uninstalls any previous install first, unpacks to `~/.local/src/omarchy-delight` and runs `install.sh` as the desktop user. |
| `vm/run <script> [args]` | Copy a host script into the guest and run it there with `bash`, as the desktop user, inside the installed checkout, with the Hyprland session's environment. Exits with its status. |
| `vm/run-all [--no-isolate] [file...]` | Run every `modules/*/tests/vm-*.sh`, `tests/e2e/vm-*.sh` and `vm/tests/vm-*.sh`, each from the same starting state, and aggregate their TAP. Exits 1 if any failed. |
| `vm/screenshot [name]` | Screenshot the desktop with `grim` in the guest (QEMU's screendump if `grim` fails). |
| `vm/snapshot NAME` | Save a snapshot of the running VM; `--list`, `--delete NAME`. |
| `vm/ssh [command]` | A shell in the guest, or one command with the session environment. |
| `vm/down` | Power off. Snapshots stay; `--destroy` deletes the machine (not the image). |

Every run writes to `vm/out/<UTC timestamp>/` (`vm/out/latest` points at the
newest; `vm/out/` is git-ignored):

```text
vm/out/20261012T093000Z/
  tap/all.tap                        aggregated TAP (one subtest per file)
  tap/<test>.tap                     each file's own TAP
  screenshots/<test>.png             the desktop after each test
  screenshots/<test>/<name>.png      vm_screenshot calls
  logs/<test>.stderr                 each test's stderr
  logs/<test>.journal                user journal, for failed tests
  logs/<test>/<file>                 vm_artifact calls
  logs/journal-user.log, journal-warnings.log, serial.log, installed-ref.txt
```

`<test>` is the file's repo path with `/` as `_`, e.g.
`modules_share_tests_vm-share`.

State lives in `$DELIGHT_VM_HOME` (default `~/.cache/omarchy-delight/vm`):
`images/<version>/` and `machine/` (overlay disk with its snapshots, SSH key,
serial log). One machine per `DELIGHT_VM_HOME`; set a different one to run two
VMs side by side.

### Timings

Measured on an 8-core KVM host (QEMU 6.2, guest with 4 vCPUs and 4 GB):

| Step | Fresh machine (`vm/up --new`) | From a snapshot |
| --- | --- | --- |
| `vm/up` | one-time 4.5 GB download, ~12 s checksum, ~17 s to boot and save `fresh` | ~2 s, VM on or off |
| `vm/install-delight main` | ~2 s | ~2 s |
| `vm/run-all` (sample test) | ~22 s | ~22 s |

`vm/up --new && vm/install-delight main && vm/run-all` takes about 40 s once
the image is cached.

## Writing a VM test

Put it at `modules/<id>/tests/vm-<what>.sh` (or `tests/e2e/vm-<what>.sh` for
cross-module flows). `tests/run` also executes files under `*/tests/` on the
host, so start with the guard that skips outside the VM:

```bash
#!/bin/bash

# share: sending a file to a paired device shows up in the Control Center.

[[ ${DELIGHT_VM:-} == 1 ]] || {
  echo "1..0 # SKIP runs inside the Delight VM (vm/run)"
  exit 0
}
# shellcheck source=vm/lib/guest.sh
source "$DELIGHT_VM_LIB"
# shellcheck source=tests/lib/tap.sh
source "$DELIGHT_ROOT/tests/lib/tap.sh"

ok "share installs" delight install share
is "share is on" "$(delight status --json | jq -r '.[] | select(.id == "share") | .state')" on
ok "the share panel opens" delight ui summon delight.share
vm_wait_for 10 hyprctl -j layers
vm_screenshot share-panel
done_testing
```

What the test can rely on:

- It runs as the desktop user `omarchy` with `bash`, its working directory is
  `$DELIGHT_ROOT` (the installed checkout) and `~/.local/bin` is on `PATH`.
- The session environment is imported from `systemctl --user
  show-environment`: `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`,
  `HYPRLAND_INSTANCE_SIGNATURE`, `DBUS_SESSION_BUS_ADDRESS`, `OMARCHY_PATH` and
  Omarchy's `PATH`. `hyprctl`, `notify-send`, `omarchy …` and `grim` behave as
  they do in a terminal on that desktop.
- `sudo -n` works, and `pacman`/`omarchy-pkg-add` reach the network, so real
  installs work (slowly; prefer to test what your module does with packages it
  installs once).
- Each file in `vm/run-all` starts from the state the VM had when `run-all`
  began (normally `fresh` plus `vm/install-delight`), so tests cannot leak into
  each other. Within one file you are on your own.
- Helpers from `vm/lib/guest.sh`: `vm_screenshot <name>` (waits for the shell to
  settle first), `vm_artifact <file>`, `vm_wait_for <seconds> <cmd…>`,
  `vm_sudo`, plus `$DELIGHT_VM_PRISTINE` (copies of `hyprland.lua` and the
  other user files Delight touches, saved before the first install).
- TAP via `tests/lib/tap.sh` (`ok`, `not_ok`, `is`, `done_testing`). A
  `# TODO` on a `not ok` line is reported but does not fail the run. Exit
  non-zero to fail even without a `not ok` line. Each file has 15 minutes
  (`DELIGHT_VM_TEST_TIMEOUT`).

Try it while writing: `vm/up && vm/install-delight . && vm/run
modules/<id>/tests/vm-<what>.sh`, then `vm/ssh` to poke around, or
`vm/snapshot before-pairing` to come back to a state quickly.

[`vm/tests/vm-harness.sh`](../vm/tests/vm-harness.sh) is the reference test: it
checks that Delight installs, `omarchy plugin list` shows
`delight.control-center`, `delight status --json` works, `hyprctl reload`
reports no config errors, and `uninstall.sh` restores `hyprland.lua` byte for
byte.

## Limitations

- **No Bluetooth, Wi-Fi or camera.** The guest has a virtio NIC behind QEMU's
  user-mode NAT, no Bluetooth controller, no wireless device and no webcam.
  Anything that needs them (pairing, AirDrop-style transfer, hotspot, Continuity
  Camera) is a `[HW]` criterion: test it on real hardware. In the VM, check that
  such modules degrade correctly, e.g. `status` reports `unsupported` with a
  reason and `doctor` exits 2.
- **One isolated guest.** NAT means the guest reaches the internet, but nothing
  on the LAN reaches it, and there is no second device to discover. mDNS and
  LAN discovery between peers cannot be tested.
- **Virtual display.** One 1920×1080 virtio-vga output (`DELIGHT_VM_RESOLUTION`),
  software rendering, no multi-monitor, no HiDPI, no audio device.
- **Screenshots, not interaction.** There is no input injection; drive the UI
  through `delight`, `hyprctl dispatch` and `omarchy` commands.
- **Stable Omarchy only by default.** The pinned image is the latest stable
  release; `DELIGHT_VM_IMAGE=latest` follows it, and a sealed directory of your
  own (`base.qcow2`, `vmlinuz`, `initrd`, `cmdline`) also works.
- **Restored clock.** A restored snapshot wakes with the time it was saved;
  `vm/up` resets the guest clock from the host.

## CI

[`.github/workflows/vm.yml`](../.github/workflows/vm.yml) runs
`vm/up --new && vm/install-delight . && vm/run-all` on demand
(`workflow_dispatch`) on a runner labelled `self-hosted, linux, kvm`, uploads
`vm/out/` as the `vm-out` artifact and prints the TAP in the job summary. Pass
`["ubuntu-latest"]` as `runner` to use GitHub's hosted runners, which expose
KVM. On a runner without a usable `/dev/kvm` the job ends green with a "VM tests
skipped" notice. The pinned image is cached between runs.
