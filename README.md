# omarchy-setup

Ansible automation for setting up a freshly installed
[Omarchy](https://omarchy.org/) desktop (4.5), with a menu to choose what
to apply.

Each automation is split into a **system phase** (packages, `/etc`, PAM,
the login screen, signed plugin builds — run by an administrator) and a
**user phase** (your `~/.config`, session services and shell plugins — run
as yourself, in your own session).

It can also set the machine up for **several users**, opt-in: the
`users`, `omarchy-multiuser` and `shared-checkout` features (all off by
default, so a stock single-owner Omarchy keeps its autologin and its own
tools) create the accounts, replace the Omarchy tools that assumed a single
owner with [omarchy-multiuser](https://github.com/lbssousa/omarchy-multiuser)
— a login screen listing everyone by full name, nobody logged in
automatically — and publish a copy every user can run their own phase
from. See [docs/multi-user.md](docs/multi-user.md) for the model.

## Choosing what to apply

Everything this repository can do is listed in [`features.yml`](features.yml),
the catalog, and documented in [docs/features.md](docs/features.md)
(generated from it): what each feature adds, modifies or removes in a stock
Omarchy, whether it is on by default, and whether turning it off undoes it.

```bash
just configure   # gum menu: pick apps and features; offers to apply them
```

- **Apps**, by category (web browsers, password managers, office suites,
  graphics, PDF viewers, video, notes, editors, file managers), each with
  its installation alternatives — native, AUR, Flathub or a release bundle
  (e.g. Firefox native or Flatpak, Brave Origin or Brave Flatpak; ONLYOFFICE,
  LibreOffice or the ArtCraft suite through its launcher). Several can be
  installed side by side; where a category has a default app (browser,
  password manager, PDF viewer, file manager) the menu asks for it. Apps
  are declarative: one left unchecked is uninstalled, Omarchy's own
  included (after a confirmation).
- **Features**, by group: accounts and login, desktop tweaks, Omarchy shell
  plugins, development tools, Portuguese (Brazil), hardware, and opt-in
  ones (Secure Boot, TPM2 auto-unlock, Homebrew, the BGRT boot theme,
  Google Drive, the Yubikey GPG key).

fish is every account's login shell; that isn't a choice. Omarchy's web
apps (YouTube, WhatsApp, ...) are rebuilt with the default browser's own
mechanism — Firefox Taskbar Tabs or Brave/Chromium PWAs — and open tiled
fullscreen.

Your choices are saved in `~/.config/omarchy-setup/features.yml`; anything
you never chose takes the catalog's default. Each user runs the menu for
their own user phase; the system phase follows the administrator's.

## Prerequisites

- An Omarchy desktop (or any Arch Linux with pacman, `locale-gen`,
  systemd and `xdg-user-dirs`).
- `run0` (part of systemd, so already there on Arch) and, for the system
  phase, a user in the `wheel` group. Other users need not be: their part is
  the user phase only.
- The libfprint playbook builds with `makepkg` on the host (no container);
  it replaces the official `libfprint`/`libfprint-git` via `pacman -U`.
- The Secure Boot playbook only covers Limine + limine-entry-tool.

Neither `just` nor `ansible` need to be pre-installed: `./bootstrap.sh`
installs `just`; `just setup` then installs `ansible` and the
`community.general` collection on its own.

### Privilege: run0 --empower

Privileged tasks escalate with [`run0`](https://www.freedesktop.org/software/systemd/man/latest/run0.html)
(the `community.general.run0` become plugin, set as `become_method` in
`ansible.cfg`). run0 authenticates through polkit, and Omarchy's shell
registers a graphical polkit agent, so a bare run0 would pop up an
authentication dialog for **every** privileged task, and polkit doesn't
retain the authorization between separate run0 processes (checked on this
machine). A playbook run has dozens of privileged tasks.

So every recipe that needs root runs ansible-playbook through
[`run-empowered.sh`](run-empowered.sh), i.e. under `run0 --empower`: the
playbook keeps running as your user (same `$HOME`, `systemctl --user`, ...)
but with all capabilities and the `empower` group, for which systemd's stock
polkit rule allows every action. You authenticate **once**, in the polkit
dialog that appears at the start (fingerprint or password, whatever the
dialog offers), and each `become: true` task's own `run0 --user=root` inside
passes without another prompt. There is no `--ask-become-pass`: no password
is handed to run0.

Nothing persists: no polkit rule granting passwordless root is installed, and
the privileges live only in that process tree while it runs. Per run0(1),
other unprivileged processes of your user have privileges over an empowered
process, so don't run a playbook while untrusted software is running in your
session.

Careful with hidden/unattended terminals: the dialog needs someone at the
screen. A caller without a human present should pass
`ansible_become_flags=--no-ask-password` (or use `run0 --no-ask-password`) to
fail fast instead of waiting.

## Usage

As an administrator, on your own account:

```bash
git clone https://github.com/lbssousa/omarchy-setup.git
cd omarchy-setup
./bootstrap.sh   # installs `just`, if missing — only needs to run once
just setup       # the menu the first time, then the system phase and your user phase
```

Later runs:

```bash
just configure            # change your choices (and apply them)
just setup                # system phase, then your user phase
just system | just user   # one phase only
just apply capslock nix   # only these features now (even if switched off)
just apply apps           # only the apps
```

Personal data stays out of the repository: your git identity, the Google
account for rclone and (administrator) the accounts' full names go in
`~/.config/omarchy-setup/local.yml` (template:
[users/local.example.yml](users/local.example.yml)).

Adding someone (turn on the multi-user features first, in `just
configure`: `users`, `omarchy-multiuser`, `shared-checkout`): declare them
in `group_vars/all/users.yml` (their full name in your `local.yml`; their
settings, if any, in `users/<name>.yml`), commit, then:

```bash
just users       # creates the account, asks for its password
just publish     # world-readable copy in /opt/omarchy-setup + omarchy-setup-user
```

They log in from the greeter (Omarchy's first-run setup runs as for the
owner) and apply their part, from a terminal in their session:

```bash
omarchy-setup-user          # same as `just user`, from the shared copy
```

`just check` syntax-checks everything, the boundary between the phases, the
catalog against the plays' tags and that docs/features.md is current
(`just docs` regenerates it). The playbooks are idempotent — rerunning is
safe.

Not Ansible, run on their own: `just typesetting` (TeX Live, LilyPond and
Gregorio on the host — see local-typesetting/README.md), `just ssh-yubikey`
/ `just ssh-yubikey-disable` (the Yubikey's resident SSH keys, prompts for
the FIDO2 PIN), `just tpm2-enroll` (interactive TPM2 enrollment) and
`just tpm2-wipe` (re-enroll after firmware or Secure Boot changes). Secure
Boot and TPM2 have walkthroughs: [docs/secureboot.md](docs/secureboot.md),
[docs/tpm2.md](docs/tpm2.md).

## Structure

| File/Directory | Role |
|---|---|
| `features.yml` | The catalog: features and apps, defaults, what each does |
| `docs/features.md` | The catalog as a document (`just docs`) |
| `scripts/configure.sh` | The gum menu (`just configure`) |
| `scripts/features.py` | Resolves the catalog with your choices; checks it (`just check`); generates the docs |
| `scripts/run-phase.sh` | Runs a phase: system only for `wheel`, under `run-empowered.sh`; user only as the user; passes `users/$USER.yml`, `local.yml`, the resolved selection and its tags |
| `scripts/check-phases.sh` | Fails when a user-phase play becomes root or installs packages, or a system-phase play talks to a user session |
| `bootstrap.sh` | Installs `just`, if missing |
| `run-empowered.sh` | Runs ansible-playbook under `run0 --empower` (see *Privilege* above) |
| `site.yml`, `system.yml`, `user.yml` | Both phases; the system phase's plays; the user phase's plays. Each play is tagged with its feature id (`apps` for the app plays) |
| `playbooks/system/`, `playbooks/user/` | One file per feature (or a few closely related ones), in its phase |
| `playbooks/{system,user}/apps/` | The app categories: packages installed or removed as chosen, then each category's extras (default apps, Firefox defaults, PWA policy, web apps, password manager keybind/autostart/SSH agent, Zathura, svg2tikz, Emacs, Zed) |
| `playbooks/tasks/` | Shared tasks: app install/removal (`app-package.yml`, `aur-build.yml`, `artcraft-launcher.yml`), Hyprland blocks (`hypr-user-block.yml`), Flatpak overrides, signed-tag checkouts, web apps, handlers |
| `playbooks/files/`, `playbooks/templates/` | Static files and Jinja2 templates |
| `group_vars/all/main.yml` | Variables for every automation (machine defaults) |
| `group_vars/all/users.yml` | The machine's accounts (`omarchy_users`); full names live in the untracked `local.yml` |
| `group_vars/all/target.yml` | `target_user`/`target_home`: the account a run configures |
| `users/<name>.yml` | Each user's own settings (see `users/README.md`), e.g. their web apps |
| `docs/` | The feature catalog, the multi-user model, Secure Boot and TPM2 walkthroughs |
| `local-typesetting/` | TeX Live + LilyPond + Gregorio on the host (`just typesetting`) |
| `requirements.yml` | Required Ansible collections |
| `Justfile` | `just configure`, `setup`, `system`, `user`, `apply`, `check`, ... |
