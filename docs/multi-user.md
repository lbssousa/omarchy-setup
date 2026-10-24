# Several users on one Omarchy machine

Omarchy is provisioned for a single owner. This repository sets the machine
up for several people instead. This page covers who runs what, how to add
someone, and what remains shared.

## The pieces

| Piece | What it does |
|---|---|
| `group_vars/all/users.yml` | Lists the accounts (`omarchy_users`). Each one has a login name, an `admin` flag, extra groups and `luks`. Everyone logs into fish. |
| `~/.config/omarchy-setup/local.yml` | Untracked personal data: git identity, the rclone account and (administrator) the accounts' full names. Template: `users/local.example.yml`. |
| `users/<name>.yml` | That user's personal settings, such as Firefox Taskbar Tabs, plugins and text size. Loaded as extra vars, so they override `group_vars` for that person only. |
| `system.yml` (`just system`) | The machine-wide half of every automation: packages, `/etc`, PAM, SDDM, udev, signed plugin builds and the accounts. Run by an administrator, under `run-empowered.sh`. |
| `user.yml` (`just user`, `omarchy-setup-user`) | The half that lives in each user's home and session. Run by each user, as themselves, inside their own Hyprland session. Nothing in it becomes root. |
| [omarchy-multiuser](https://github.com/lbssousa/omarchy-multiuser) | Forks of the Omarchy tools that assumed one owner: the greeter, autologin, FIDO2, fingerprint, lock screen PAM and migrations. Installed from a signed tag by `system/omarchy-multiuser.yml`. |

`scripts/run-phase.sh` enforces the split. The system phase is refused to
anyone outside `wheel`, and the user phase is refused to root and to
empowered processes. `scripts/check-phases.sh` (`just check`, CI) keeps
user-phase plays from becoming root or installing packages, and keeps
system-phase plays from reaching into a user session.

## Administrators and everyone else

Administrators are in `wheel`. They run the system phase, use `sudo`, and
see the machine-wide entries in the Omarchy menu (Install, Style › Unlock,
sshd, passwordless sudo, the disk password, Setup › Users).

Everyone else is in `omarchy-users`. Through omarchy-multiuser's sudoers
rules they can:

- register and remove **their own** FIDO2 keys (Setup › Security › Fido2).
  Their line in the shared `/etc/fido2/fido2` is the only one they can touch.
- enroll and delete **their own** fingerprints (Setup › Security ›
  Fingerprint). fprintd allows this without root. Fingerprint unlock on the
  lock screen stays on while any user has prints.
- apply their Omarchy migrations (Update › Omarchy), as described below.

## Adding a person

1. Add them to `group_vars/all/users.yml` and commit. Their full name,
   which the greeter lists, goes in `omarchy_user_full_names` in the
   administrator's untracked `~/.config/omarchy-setup/local.yml` (see
   `users/local.example.yml`). If they want, also create
   `users/<name>.yml` (see `users/README.md`).
2. Run `just users`. This creates the account (home seeded from
   `/etc/skel`), asks for its password and, with `luks: true`, offers a disk
   unlock password of their own.
3. Run `just publish`. This refreshes `/opt/omarchy-setup` (the committed
   HEAD) and `omarchy-setup-user`.
4. They log in from the greeter. Omarchy's first-run setup runs as it did
   for the owner: theme, keyring and user services.
5. They run `omarchy-setup-user` in a terminal, or use Setup › Omarchy Setup.
   This applies the user phase with their settings. It can be re-run at
   any time and changes nothing that's already in place.

`omarchy-mu-user-add` (Setup › Users › Add User) does steps 1–2 by hand,
outside Ansible. `omarchy-mu-user-remove` removes an account along with its
FIDO2 line, prints and disk keyslot. Removing someone from `users.yml` does
**not** delete their account.

## The login screen

The greeter (`omarchy-multiuser` SDDM theme) is Omarchy's own, with a list
of users above the password field. Each account appears by full name, or by
login name when GECOS is empty. The last user is preselected. The last row,
**Outro usuário… / Other user…**, reveals a field for typing any username.
↑/↓ switch users, Tab moves between the fields, Enter logs in.

Nobody is logged in automatically. Omarchy keeps the owner logged in for
good on encrypted installs. `zz-omarchy-multiuser.conf` overrides that, and
`omarchy-mu-sddm-guard` removes `autologin.conf` whenever Omarchy writes it
back.

The disk password and the login password are separate prompts. With
`luks: true` each person can have their own disk password
(`omarchy-mu-luks-enroll`), but the boot prompt is the same for everyone.
Keep a LUKS header backup.

## Migrations

`omarchy-update` upgrades system packages, then runs the caller's
migrations. That is administrator work. Migrations are tracked per user,
and many of them need `sudo`, so on stock Omarchy a user outside `wheel`
would stall at the first one and be asked to retry at every login.

omarchy-multiuser records each migration an administrator has run (in
`/var/lib/omarchy-multiuser/migrations`). At login, for everyone else, it
works through the pending migrations in order:

- migrations that only touch `$HOME` run as usual;
- privileged-only migrations are marked done once an administrator has run
  them;
- mixed migrations run their `$HOME` part after that, with `sudo` skipped
  and logged.

A migration waiting for an administrator stays pending quietly. A user is
notified only when one actually fails (log:
`~/.local/state/omarchy-multiuser/migrate.log`).

## What stays shared

| What | Why | Where |
|---|---|---|
| Packages, `/etc/locale.conf`, keyd, the printer queue, Plymouth, Limine | They belong to the machine | system phase |
| Homebrew | One prefix with one owner (`homebrew_owner`); others can run what it installed | `system/homebrew.yml` |
| The greeter's colors | Style › Unlock recolors the login screen for everyone, so only administrators see it in the menu | omarchy-multiuser |
| The browsers' theme color policy | Omarchy writes it to `/etc` on every theme change, and its sudoers rule is `%wheel`. The last administrator to change theme wins; other users' theme changes leave it alone. | Omarchy |
| Tailscale `--operator` | Tailscale allows a single operator | Omarchy |
| Omarchy's own `omarchy-remove-security-*` commands | Still installed. Called directly, they remove FIDO2 or fingerprints for everyone; the menu points at the per-user forks | Omarchy |
| Fast user switching | Not set up: one graphical session at a time, from the greeter | — |

## Undoing it

`pacman -R omarchy-multiuser` brings Omarchy's greeter back, and the
upstream commands keep working as before. Autologin stays off until you turn
it back on. Accounts stay until removed with `omarchy-mu-user-remove` or
`userdel`.
