# Several users on one Omarchy machine

Omarchy is provisioned for a single owner. This repository can set the
machine up for several people instead. This page covers who runs what, how
to add someone, and what remains shared.

All of it is opt-in: the `users`, `omarchy-multiuser` and `shared-checkout`
features are off by default. Turn them on in `just configure` (or once with
`just apply users omarchy-multiuser shared-checkout`).

## The pieces

| Piece | What it does |
|---|---|
| `group_vars/all/users.yml` | Lists the accounts (`omarchy_users`). Each one has a login name, an `admin` or `child` flag and extra groups. Everyone logs into fish. |
| `~/.config/omarchy-setup/local.yml` | Untracked personal data: git identity, the rclone account and (administrator) the accounts' full names. Template: `users/local.example.yml`. |
| `~/.config/omarchy-setup/features.yml` | That user's choices from `just configure`: which apps and features apply. The user phase follows each user's own; the system phase follows the administrator's. |
| `users/<name>.yml` | That user's personal settings, such as their web apps, plugins and text size. Loaded as extra vars, so they override `group_vars` for that person only. |
| `system.yml` (`just system`) | The machine-wide half of every automation: packages, `/etc`, PAM, SDDM, udev, plugin builds and the accounts. Run by an administrator, under `run-empowered.sh`. |
| `user.yml` (`just user`, `omarchy-setup-user`) | The half that lives in each user's home and session. Run by each user, as themselves, inside their own Hyprland session. Nothing in it becomes root. |
| [omarchy-multiuser](https://github.com/lbssousa/omarchy-multiuser) | Forks of the Omarchy tools that assumed one owner: the disk prompt, the greeter, the lock screen and its PAM, autologin, passwords, FIDO2, fingerprint, migrations, child accounts and per-user blocked apps. Installed from a release tag by `system/omarchy-multiuser.yml`. |

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
- change **their own** password and disk key (Setup › Users › Change
  Password).
- apply their Omarchy migrations (Update › Omarchy), as described below.

A **child** account (`child: true` in `group_vars/all/users.yml`, or
`omarchy-mu-user-add --child`) is a limited account also in `omarchy-child`,
with no other groups: it starts with messaging, social and work web apps
blocked (`omarchy-mu-user-apps`, Setup › Users › Blocked Apps, which denies
binaries via ACLs and hides desktop entries per person), and an
administrator's password also unlocks their lock screen (`adult-check`, rate
limited and logged).

What would only end in a refusal stays out of their way: the menu hides
the machine-wide entries, the bar's update icon comes off their bar at their
first login (it comes back where it was if they become administrators), and
polkit refuses them the browsers' theme color policy without asking for an
administrator's password.

## Adding a person

1. Add them to `group_vars/all/users.yml` and commit. Their full name goes
   in `omarchy_user_full_names` in the
   administrator's untracked `~/.config/omarchy-setup/local.yml` (see
   `users/local.example.yml`). If they want, also create
   `users/<name>.yml` (see `users/README.md`).
2. Run `just users <name>`. This creates the account (home seeded from
   `/etc/skel`) and asks for its password and yours
   (`omarchy-mu-user-password`). It has at least 6 characters, is nobody
   else's, and on an encrypted disk is also their own key to it. They can
   change it later from Setup › Users › Change Password. (Running `just users`
   without arguments updates existing accounts without creating new ones.)
3. Run `just publish`. This refreshes `/opt/omarchy-setup` (the committed
   HEAD) and `omarchy-setup-user`.
4. They type their password at the disk prompt, or on the login screen.
   Omarchy's first-run setup runs as it did for the owner:
   theme, keyring and user services.
5. They run `omarchy-setup-user` in a terminal, or use Setup › Omarchy Setup.
   This applies the user phase with their settings. It can be re-run at
   any time and changes nothing that's already in place.

`omarchy-mu-user-add` (Setup › Users › Add User) does steps 1–2 by hand,
outside Ansible. `omarchy-mu-user-remove` removes an account along with its
FIDO2 line, prints, disk key and the sudo grants that would outlive it
(the installer's by name, passwordless sudo's by UID). Removing someone from
`users.yml` does **not** delete their account.

`omarchy-mu-user-admin <name> on|off` (Setup › Users › Administrator
Rights) gives or takes away administrator rights by hand. Taking them
deletes the account's sudo grants before it leaves `wheel`, and offers to
log the person out, since programs already open keep `sudo` until then.
Setting `admin: false` in `users.yml` and running `just users` does the same,
except the logout. Neither takes away your own rights.

Root's password is the owner's on a fresh Omarchy, and from then on follows
its holder (`/etc/omarchy-multiuser/root`): the first administrator who makes
a change with the password root has. Because every password is its person's
alone, only the holder knows root's. Changing the holder's password changes
root's in the same write; removing the holder hands root to the administrator
removing them; taking the holder's administrator rights away hands it over
first (`omarchy-mu-user-helper root-take`).

## The disk prompt and the login screen

Each person's password is also their own LUKS key slot, recorded in
`/etc/omarchy-multiuser/slots`. Change it with `omarchy-mu-user-password`
(Setup › Users › Change Password), never `passwd`, which would leave the disk
key behind. Administrators can change anyone's. Update › Password › Drive
Encryption (`omarchy-mu-drive-password`) leaves the system disk out once
accounts have their own keys.

The password typed at the disk prompt says who is there: that person's
desktop opens, once, without a second prompt. With a single account on an
encrypted disk, it is logged in, as on stock Omarchy, unless the disk has a
token (TPM2, FIDO2, clevis). Anything unsure, a TPM2 unlock among them, shows
the login screen.

The greeter (`omarchy-multiuser` SDDM theme) is Omarchy's own, with a password
box alone: it finds the account by the password. There is no list of users
and no username field.

The greeter runs at 100% scale (`omarchy_greeter_monitor_scale`, feature `text-size`), whatever
scale each user picks for their own session.

Omarchy's own `autologin.conf` is removed whenever Omarchy writes it back
(`omarchy-mu-sddm-guard`); the package writes its own, for one start, for
whoever unlocked the disk. Keep a LUKS header backup.

## The lock screen

The lock screen is Omarchy's own, with **Trocar de usuário** (F5), **Suspender**
(F1), **Reiniciar** (F3) and **Desligar** (F4) at the bottom, each only when the
machine can do it. Reiniciar and Desligar ask first, since they end everyone's
sessions, and anyone at the keyboard can use them.

**Trocar de usuário** opens the login screen while the session stays locked
behind it. Coming back to that session through the login screen asks for the
password once. Each account gets this lock screen at its next login. To go back
to Omarchy's, run `omarchy plugin disable lbssousa.lock`; it stays off for that
account.

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
| Packages, `/etc/locale.conf`, the printer queue, Plymouth, Limine | They belong to the machine | system phase |
| Homebrew | One prefix with one owner (`homebrew_owner`); others can run what it installed | `system/homebrew.yml` |
| The greeter's colors | Style › Unlock recolors the login screen for everyone, so only administrators see it in the menu | omarchy-multiuser |
| The browsers' theme color policy | Omarchy writes it to `/etc` on every theme change, and its sudoers rule is `%wheel`. The last administrator to change theme wins; for anyone else omarchy-multiuser's polkit rule refuses it without a prompt, so their theme changes leave it alone. | Omarchy, omarchy-multiuser |
| Tailscale `--operator` | Tailscale allows a single operator | Omarchy |
| Omarchy's own `omarchy-remove-security-*` commands | Still installed. Called directly, they remove FIDO2 or fingerprints for everyone; the menu points at the per-user forks | Omarchy |
| Fast user switching | Not set up: one graphical session at a time, from the greeter | — |

## Undoing it

`pacman -R omarchy-multiuser` brings Omarchy's greeter back, and the
upstream commands keep working as before. Each person's disk key stays on
the disk, and `/etc/omarchy-multiuser/slots` says whose is whose. Autologin
stays off until you turn it back on. Accounts stay until removed with `omarchy-mu-user-remove` or
`userdel`.
