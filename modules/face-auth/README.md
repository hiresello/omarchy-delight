# Face unlock

Convenience IR face unlock for the Hyprland lock screen. It is not Windows
Hello, and it is never the only factor for login, polkit, disk unlock, or a
password manager. The threat model, including what Howdy Next does not stop,
is `docs/face-auth-threat-model.md`.

Face can succeed at the lock screen only after a password has already worked
since boot, and only until the next suspend (the default) or a faillock
lockout. A face match does not refresh that password stamp. `sudo` is off
unless you turn it on, and even then the face window is at most fifteen
minutes after a real password.

## Commands

```bash
delight face-auth install
delight face-auth enable
delight face-auth validate
sudo delight face-auth apply --dry-run
sudo delight face-auth apply
sudo /usr/local/sbin/delight-face-auth-disable
```

`install` adds the `howdy-next` package when you ask it to. `enable` checks
the policy and writes a preview under `~/.config/omarchy-delight/face-auth/`.
Neither command edits `/etc/pam.d`. Status stays `needs-setup` ("PAM not
applied") until `apply` has written a manifest.

`validate` renders the stack and rejects it if the PAM shape, the faillock
numbers, or the simulated outcomes are wrong. `apply` does that again, refuses
a template directory that does not look like it sits on an encrypted mount,
tightens model-file permissions, and only then replaces PAM. A failed check
leaves the live files alone. `--dry-run` audits and prints the plan without
writing.

`sudo howdy disable 1` stops recognition and leaves PAM in place. Use the
disable script when you want the previous PAM files back. Rollback does not
need `jq` or the `delight` CLI.

Before `apply`, enroll and test with Howdy's own tools. Do not point Howdy at
`/dev/videoN`.

```bash
sudo howdy config
sudo howdy add
sudo howdy test
```

Use `/dev/v4l/by-path/` or `/dev/v4l/by-id/` in Howdy's config. If you set
`device_path` in this module's policy, it has to be one of those paths. The
module never writes `/etc/howdy/config.ini`. Invalid keys there are rejected
by `howdy config`. The preview file `recommendations.txt` says not to lower
`sface_threshold` and not to save frames.

## Policy

Keys live under `face-auth` in `~/.config/omarchy-delight/config.json`. Unknown
keys are rejected. `enabled` is the module switch and is not part of the
policy check.

| Key | Default | Range |
|---|---|---|
| `scope.hyprlock` | `true` | Lock screen. Both scopes `false` installs no PAM file |
| `scope.sudo` | `false` | Optional. Face only inside the cache below |
| `sudo_cache_seconds` | `300` | 1–900, checked even when sudo is off |
| `suspend_max_seconds` | `0` | 0–86400. `0` means every suspend, hibernate, or hybrid-sleep requires a password |
| `deny` | `5` | 3–10 faillock failures |
| `fail_interval` | `900` | 60–86400 seconds |
| `unlock_time` | `600` | 60–86400 seconds |
| `allow_unencrypted_models` | `false` | `true` lets `apply` proceed on a mount that does not look encrypted |
| `device_path` | empty | Empty, or a `/dev/v4l/by-path/` or `by-id/` path with no `..` and no spaces |

A face miss and a wrong password are both counted. With `deny` at 5, two or
three prompts that fail both ways lock the account for `unlock_time`. Face
cannot skip that lock. A later correct password clears it. Root is not
included in the lockout, so a text-console root login can still recover.

Model files Howdy already created are forced to mode `0600` in a `0700`
directory, owner root, with symlinks refused. There is no second encryption
step. At rest, the protection is the encrypted volume those files sit on.

## Break-glass

The login PAM stack is untouched. A bad hyprlock file does not remove the
password on a text console.

1. Keep a root shell open while you test `apply`.
2. If the lock screen will not accept the password: Ctrl+Alt+F3, then log in
   with the account password. F2 through F6 are the usual other consoles.
3. Restore the previous PAM files:

   ```bash
   sudo /usr/local/sbin/delight-face-auth-disable
   ```

   This reads `/var/lib/omarchy-delight/face-auth/manifest`, copies backups
   from `/var/lib/omarchy-delight/face-auth/backup/`, deletes files the apply
   created, and removes the gate, the stamp helper, and the sleep hook. It
   leaves the script itself in place. Running it again, with no manifest,
   exits 0.

4. If that script is gone, restore from the manifest by hand as root. The
   first line is `v1`. Each other line is the path, a tab, `replace` or
   `create`, a tab, and a backup name or `-`. `replace` means copy the backup
   onto the path. `create` means delete the path. Then delete the manifest.
   Do not edit `/etc/pam.d/system-auth` to get out of this.

5. `delight face-auth disable` as a normal user, while the manifest still
   exists, only marks the module off and then tells you to run the root
   script. hyprlock keeps the face stack until the script runs.

The full procedure, including recovery media if local login is unreachable,
is in `docs/face-auth-threat-model.md`.
