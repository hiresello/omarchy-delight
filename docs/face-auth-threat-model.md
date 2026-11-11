# Face authentication threat model

Checked against upstream pages on 11 November 2026. This is the security
note for the `face-auth` module on the ASUS Zenbook A16 (UX3607OA, Snapdragon
X2 Elite Extreme). The goal Juan asked for is Windows Hello reliability and
security. That parity is not available on this laptop, and this module does
not claim it.

The module is a convenience unlock for an already-authenticated session. The
password remains the credential. When a choice is unclear, the password is
required.

## What is actually installed

Default scope is the Hyprland lock screen (`/etc/pam.d/hyprlock`) only. `sudo`
is off. Login, the greeter, polkit, disk unlock, ssh, `su`, and the password
manager are never given a Howdy line.

`install` and `enable` do not edit `/etc/pam.d`. They render a preview under
`~/.config/omarchy-delight/face-auth/`. The live stack is a separate root
step, `delight face-auth apply`, and only after `delight face-auth validate`
accepts the rendered files. `apply --dry-run` prints the plan and writes
nothing.

A face match can unlock hyprlock only when all of these are true:

- A real password has succeeded once since boot (a root-only stamp in `/run`).
- Nothing has asked for a password again (the default is that every suspend,
  hibernate, or hybrid-sleep does).
- The account is not in a `pam_faillock` lockout.
- The gate script exits 0. Any doubt, including a missing or symlinked stamp,
  skips Howdy.

A face match does not refresh that stamp, so face success cannot extend the
optional `sudo` window. A face miss still asks for the password. There is no
`pam_permit`, no `nullok`, no `include` of `system-auth`, and no
`workaround=` option. Howdy is not `sufficient` on its own.

## Attacker models

### Photo or video replay

Someone holds a phone or a laptop screen up to the camera, or plays a video
of the enrolled person.

Howdy Next's own warning says a photo may fool it, and that IR light is not
reproduced by photos or LCD displays, so an IR camera reduces that class of
spoof relative to a normal webcam. That is the project's claim. It is not a
measurement on this laptop, and it is not liveness. A recording or a screen
that does emit or reflect near infrared is outside what that sentence covers.

This module adds no extra replay check. The lock-screen gate only decides
whether Howdy is allowed to run.

### IR photograph or print

Someone prints a picture that reflects the laptop's IR illuminator, or shows
an image captured by another IR camera.

Howdy Next 3.4.2 does not document a liveness or anti-spoof stage. The
configuration guide exposes detection and match thresholds (`yunet_score_threshold`,
`sface_threshold`, CLAHE, `dark_threshold`). Lowering `sface_threshold` makes
matching easier and less strict. None of those keys test whether the face is
alive.

A research patch for classic Howdy, [howdy-liveness](https://github.com/collingeorge/howdy-liveness)
(README v1.4, March 2026), reports passive IR reflectance checks on a 2019
Surface Pro USB IR camera with Howdy 2.6.1: the author's table says 38/38
printed photos and 34/34 phone screens were rejected at a threshold calibrated
on that machine. The same README says 3D masks were not tested, the threshold
is hardware-specific, and the code patches Howdy's Python `compare.py`. That
is not Howdy Next, and it is not this laptop's MIPI camera. This module does
not ship that patch and does not treat those counts as evidence here.

### Sleeping, absent, or forced person

The enrolled person is asleep, looking away, or being made to face the camera.

Windows Hello face, on hardware Microsoft qualifies, requires the head to be
within about ±15° of the camera before it will decide. Howdy Next's README
does not document an equivalent pose, blink, gaze, or challenge check. A face
that embeds close to the template can match with eyes closed. This module
does not add one. Physical presence of the enrolled face is enough for the
lock screen once a password has been used since boot.

That is why face is not wired to login, polkit, disk unlock, or the password
manager. Those stay password (or the device's existing factor). The lock
screen is the only place a matching face can succeed without typing, and only
inside the window above.

### Evil maid

Someone with the machine, time, and a way to get root or to boot their own
media.

- They can enroll a second face with `sudo howdy add` if they already have
  root. File modes do not stop root.
- They can replace a PAM file or the gate script. `apply` refuses a symlink
  at the destination, and a later `validate` or `doctor` fails if the
  installed stack is no longer the generated one. That detects a change only
  when someone runs those commands. It does not stop a root user.
- Offline, the templates sit on the encrypted root volume. A locked disk is
  the barrier. There is no second encryption layer and no TPM seal. After the
  volume is open, root reads the templates.
- `pam_faillock` is not configured with `even_deny_root`. Locking the user
  account must not lock the break-glass root login. That also means a root
  password is not disabled by these counters.

### Local malware reading templates

A process running as the logged-in user.

Templates are tightened to owner-only `0600` files in `0700` directories when
`apply` can see them (`/etc/howdy/models`, `/var/lib/howdy`,
`/usr/lib/security/howdy/models`, `/usr/lib64/security/howdy/models`, and
`/etc/howdy/config.ini`). Symlinks and special files are refused. A normal
user process should not be able to read them.

Root malware can. Howdy has to read the templates as root at unlock time, so
any key root can use is a key root malware can use. Matching runs in the
normal kernel, not in an isolated matcher. Malware that is already root can
also read the camera, hook `pam_howdy.so`, or sit on the PAM stack. Face
unlock does not make that worse than the root compromise, and it does not
contain it.

`apply` refuses to install PAM if the template directory's mount does not
look like dm-crypt, LUKS (`/dev/mapper/` or a `crypt` source), or ecryptfs,
unless `allow_unencrypted_models` is explicitly true. That flag is a
deliberate downgrade. The check is a mount-table heuristic, not a proof that
the volume is sealed to this machine.

## What Howdy Next mitigates, and what it does not

Fetched from the project on 11 November 2026: [Howdy Next](https://github.com/nathawatc/howdy-next)
`README` on `main` (CMake project version 3.4.2; AUR `howdy-next` 3.4.2-2),
the [Configuration](https://github.com/nathawatc/howdy-next/wiki/Configuration)
wiki, and the [PAM Integration](https://github.com/nathawatc/howdy-next/wiki/PAM-Integration)
wiki.

The README warning, quoted because it is the project's own limit:

> Howdy is weaker than a password. Similar faces or photos may fool it.
> IR reduces spoofing because IR light is not reproduced by photos or LCD displays.
> Never use Howdy as the sole authentication method.

What that gives us, if the IR camera is the one Howdy opens:

- A normal color photo or an ordinary LCD is a weaker spoof against the IR
  sensor than against a webcam. Howdy states this as a property of IR light,
  not as a tested false-accept rate.
- Recognition can be turned off without deleting models: `sudo howdy disable 1`
  (wiki Troubleshooting, "Disable Temporarily"). Turning it back on is
  `sudo howdy disable 0`. This does not undo a PAM file. A broken stack still
  needs the rollback below.
- The camera path should be `/dev/v4l/by-id/` or `/dev/v4l/by-path/`, not
  `/dev/videoN`, so a device renumber does not point Howdy at a different
  sensor. This policy rejects any other `device_path`.

What it does not give us:

- No published liveness, gaze, blink, or challenge-response in Howdy Next
  3.4.2. Searching the README and the configuration wiki shows threshold and
  camera keys, not an anti-spoof module.
- No false-accept number comparable to Windows Hello. Do not borrow
  Microsoft's 1/100,000 figure and apply it to Howdy.
- No secure path from the camera into the matcher. The frames are ordinary
  V4L2 data in normal Linux processes.
- The upstream PAM examples are looser than this module. The wiki's Arch
  example puts `pam_howdy.so` in `system-auth` with `workaround=native`, which
  would offer face to every service that includes that stack. The graphical
  example uses `auth sufficient pam_howdy.so`. This module does not follow
  either example. It writes only `hyprlock` and, if enabled, `sudo`, and the
  validator rejects `system-auth`, `login`, `polkit-1`, `sshd`, `sufficient`
  Howdy, `workaround=`, `nullok`, `pam_permit`, and `even_deny_root`.

`sudo howdy config` is the supported way to edit `/etc/howdy/config.ini`.
Howdy rejects unknown keys. This module never writes that file. A
`recommendations.txt` preview lists the camera path and asks the operator not
to lower `sface_threshold` and not to save frames of successful or failed
attempts. A saved frame is a photo of whoever was at the camera.

## How this differs from Windows Hello with Enhanced Sign-in Security

Microsoft's [Windows Hello face authentication](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/windows-hello-face-authentication)
page (updated 15 July 2021) describes a near-infrared pipeline: find landmarks,
require the head within ±15°, build a representation rather than store an
image, and compare it on the device. For the Windows 11 algorithm, Microsoft
publishes a false-accept rate below 0.001% (1 in 100,000) and a true-positive
rate above 95% for a single enrolled user. Those numbers are Microsoft's, for
Windows Hello, on hardware they qualify. They are not measurements of Howdy
Next and not measurements of this laptop.

[Enhanced Sign-in Security](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/windows-hello-enhanced-sign-in-security)
(updated 19 February 2026) is a different bar again:

- The face algorithm runs in Virtualization Based Security. The hypervisor
  limits which memory the camera may write, and templates are encrypted with
  keys that only that isolated environment can use.
- A successful match authorizes Windows Hello keys through a channel to
  TPM 2.0 that VBS set up at boot.
- Face ESS, as that page describes the compatibility check, is a USB camera
  using the inbox UVC driver, with `CM_DEVCAP_SECUREDEVICE` on the camera and
  on a USB host controller, plus a Secure Devices (SDEV) ACPI table.

This laptop's cameras are MIPI CSI-2 (OV02C10 color, HM1092 IR), not USB UVC
devices sitting behind that host-controller check. The feasibility note for
this machine found no usable TPM device under Linux, so there is no equivalent
seal to build on. ESS is something the manufacturer
turns on when the hardware, drivers, and firmware qualify. A Copilot+ PC
shipping Windows with ESS on does not create an ESS environment under Arch.
Nothing in this module isolates the matcher, encrypts templates to a
hardware key, or authorizes a TPM-held credential.

Older public work, including the 2018 IR-photo spoof written up by
[Sophos](https://nakedsecurity.sophos.com/2018/01/05/windows-hello-face-recognition-fooled-by-a-photograph/),
showed that an IR print could pass Windows Hello face on some devices of that
era. That article is history. It is not a current test of ESS, and it is not
a reason to claim ESS is broken. It is a reason not to treat "the camera is
infrared" as liveness.

## Failure limits

`pam_faillock` wraps the stack. Defaults, and the accepted ranges:

| Key | Default | Accepted | Meaning |
|---|---|---|---|
| `deny` | 5 | 3–10 | Failures inside `fail_interval` lock the account |
| `fail_interval` | 900 | 60–86400 seconds | Window those failures are counted in |
| `unlock_time` | 600 | 60–86400 seconds | How long the lock lasts |
| `sudo_cache_seconds` | 300 | 1–900 | How long after a password `sudo` may try face |
| `suspend_max_seconds` | 0 | 0–86400 | `0` means every suspend needs a password again |

Upstream `pam_faillock` commonly defaults to `deny=3`, `fail_interval=900`,
`unlock_time=600`. This module uses `deny=5` because a face miss and a
following wrong password are both recorded. One bad prompt can add two
tallies. With the default, two or three prompts that fail both ways reach the
lock. A later password success clears the tally. While the account is locked,
`preauth` fails the stack before Howdy or `pam_unix` run, so face cannot skip
the lockout.

`sudo` face, when the operator turns it on, still requires a password after
reboot, after the cache (default five minutes, at most fifteen), after the
suspend rule, and after lockout. Face success does not move the stamp.

After reboot, `/run` is empty, so the first hyprlock unlock needs a password
too. The first graphical login needs a password because this module never
edits the login stack.

## Explicit non-goals

- Windows Hello or ESS parity, including Microsoft's published accuracy.
- A TPM- or Pluton-sealed template, a secure camera path, or a measured boot.
- Liveness, blink, gaze, or 3D-mask resistance. Third-party writeups of those
  ideas are not an audit of Howdy Next 3.4.2 and are not enabled here.
- Shipping howdy-liveness or any other Howdy fork.
- A second encryption layer on the model files.
- Face on login, polkit, disk unlock, ssh, or a password manager.
- Face as a fallback that skips a required password.
- Editing kernel patches, the IR camera shim, or the camera probe. Those are
  not this change.
- Overwriting `/etc/howdy/config.ini`, or chmod of OpenCV model files under
  `/usr/share`.

## Logging

The gate, the stamp, the sleep hook, and the rollback script log with
`logger -t delight-face-auth`. A logger failure is ignored so logging cannot
block unlock or suspend. Howdy's own PAM errors go to the `pam_howdy` syslog
tag (`journalctl -b -t pam_howdy`, as the Howdy README says). These logs do
not store camera frames.

```bash
journalctl -t delight-face-auth -b
```

## Break-glass

Do this before the first real `apply`, and keep it available afterwards. The
login stack is not modified, so a text console still accepts the password
even when hyprlock's PAM file is wrong.

1. Leave a root shell open in another terminal while testing `apply`. The
   Howdy PAM wiki asks for the same thing.
2. If the lock screen will not take the password, switch to a text console:
   Ctrl+Alt+F3 (F2 through F6 are the usual alternatives). Log in with the
   user name and the account password.
3. Roll the PAM files back. This does not need the `delight` CLI or `jq`:

   ```bash
   sudo /usr/local/sbin/delight-face-auth-disable
   ```

   The script reads `/var/lib/omarchy-delight/face-auth/manifest`. Lines
   marked `replace` are copied back from
   `/var/lib/omarchy-delight/face-auth/backup/`. Lines marked `create` are
   deleted. It also removes the gate, the stamp helper, and the sleep hook.
   It does not remove itself, so it can be run again. A second run with no
   manifest prints that face auth is already disabled and exits 0.

   The same restore is `sudo delight face-auth rollback` when the CLI is
   still on `PATH`.

4. If the disable script is missing, do the copy by hand from a root shell.
   The manifest is tab-separated. The first line is `v1`. Other lines are
   `path`, then `replace` or `create`, then a backup file name or `-`.
   For `replace`, copy `backup/<name>` onto the path. For `create`, delete
   the path. Then delete the manifest. Do not edit
   `/etc/pam.d/system-auth` as a shortcut.

5. `sudo howdy disable 1` only stops recognition. Use it when the camera
   misbehaves and the PAM files are still the ones `apply` wrote. Use the
   disable script when a PAM file itself is the problem.

6. Root is not covered by `even_deny_root`. If the user account is in a
   faillock lockout, a root login on the text console can still run the
   disable script. Do not add `even_deny_root` to clear a lock faster. That
   option can lock the recovery account too.

7. If the machine will not reach a local login at all, boot recovery media,
   unlock the disk, and restore the `backup/` files the same way. Nothing in
   this module changes the initramfs or the disk-unlock prompt.

After rollback, hyprlock uses whatever PAM file was there before `apply`.
`delight face-auth disable` from a normal user, while a manifest still
exists, marks the module off in its config and then exits with an error that
tells you to run the root script. Until that script runs, hyprlock still uses
the face stack. The config flag does not remove PAM. Run
`sudo /usr/local/sbin/delight-face-auth-disable` first if you want the lock
screen back on its previous PAM file, then `disable` only updates config.
