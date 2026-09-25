# omarchy-setup

Ansible automation for setting up a freshly installed
[Omarchy](https://omarchy.org/) desktop.

Each automation is a play under `playbooks/`, imported by `site.yml`;
automations that depend on each other (Podman → Distrobox, snapd → VS Code,
TeX Live → Gregorio, the OpenSSH agent → KeePassXC) or that share a theme
(the desktop tweaks, the Yubikey helpers) live together in one playbook
file. All of them share the same privilege escalation (run0, see
`ansible.cfg`), and each automation has its own tag: run one with
`--tags <tag>`, or skip one with `--skip-tags <tag>`. A tag that names a
play with a dependency also runs the play it depends on first (e.g.
`--tags distrobox` sets Podman up first), and files with several plays
have an umbrella tag for the whole file (`containers`, `snap`, `desktop`,
`tex`, `yubikey`). Exceptions:
`playbooks/secureboot.yml`, `playbooks/bgrt-theme.yml`,
`playbooks/apparmor.yml`, `playbooks/keepassxc.yml`, `playbooks/bitwarden.yml`,
`playbooks/proton-pass.yml`, `playbooks/tex.yml` (TeX Live + Gregorio),
`playbooks/yubikey.yml` and `playbooks/brave-pwa-webapps.yml` are **not**
imported by `site.yml` — Secure Boot, the
BGRT boot theme and AppArmor touch firmware/boot, KeePassXC, Bitwarden and
Proton Pass are three alternative password managers (install whichever one
you want — none of them is the default), TeX Live (+ Gregorio, which
depends on it) is a long download/install you run on demand, the
Yubikey helpers need the physical token plugged in, and each
`brave_pwa_webapps` entry reflects a personal container layout over
Omarchy's default (its container has to already exist in Brave) — so they
only run when called explicitly.

## What it sets up

| Automation | Tag | What it does |
|---|---|---|
| Firefox | `firefox` | Installs Firefox and enables tab apps (Taskbar Tabs), off by default on Linux. Runs before pt-BR localization. |
| Brave PWA web apps | `brave-pwa-webapps` | `brave_pwa_webapps` in `group_vars/all/main.yml` (currently WhatsApp, Microsoft Teams and YouTube) force-installs each url as a Brave web app via the `WebAppInstallForceList` machine policy, discovers the app id Brave assigns it, then overwrites the matching Omarchy web app launcher to open that app id inside `container_name` (`--app-id=... --container=...`) and rebinds its Hyprland keybind to it — see `playbooks/tasks/brave-pwa-webapp-swap.yml`. Each `container_name` must already exist as a Brave container (hamburger menu → Containers → New — no CLI to create one). Needs root; not part of `just setup`. |
| Zed editor | `zed` | Installs Zed + omazed (Omarchy theme integration), sets every font size (UI, buffer, agent, terminal) to 25px and the buffer font to JetBrainsMono Nerd Font, and sets `use_podman` so Dev Containers use Podman instead of Docker. |
| gregorio-lsp | `gregorio-lsp` | Installs Rust (`omarchy install dev-env rust`) if needed, then builds and installs the `gregorio-lsp`, `grelint` and `grefmt` binaries from source. |
| PDF viewer | `pdf-viewer` | Installs Zathura (+ MuPDF backend) as the default PDF viewer and Papers as an extra, non-default viewer. Evince stays installed since Nautilus's sushi previewer depends on it. |
| pinentry-omarchy | `pinentry` | Builds and installs [pinentry-omarchy](https://github.com/lbssousa/pinentry-omarchy) (Rust pinentry + omarchy-shell plugin) from its own PKGBUILD, installing Rust first if needed. It builds the release tag in `pinentry_omarchy_ref` only after verifying the tag's GPG signature against the Yubikey's key (`pinentry_omarchy_signing_keys`). Links and enables the `lbssousa.pinentry` shell plugin and sets `pinentry-program` in `~/.gnupg/gpg-agent.conf`, so GnuPG PIN and passphrase prompts (e.g. the Yubikey card PIN) use the same overlay dialog as the polkit agent. Without a Wayland session it falls back to pinentry-gnome3/curses. Must run inside the graphical session (enabling the plugin goes through the shell's IPC). |
| GTK4 file dialogs | `file-chooser` | Makes the open/save file dialogs of non-GNOME apps (Firefox, Chromium, Electron, GTK and Qt apps) the GTK4 ones. Installs `xdg-desktop-portal-gnome` (its FileChooser is Nautilus's) and routes the FileChooser portal to it for Hyprland (`~/.config/xdg-desktop-portal/hyprland-portals.conf`), clears the session's forced `GDK_BACKEND` for that one service (otherwise it starts in a settings-only mode and shows no dialogs), and exports `GTK_USE_PORTAL=1` from `~/.config/hypr/hyprland.lua`. Qt apps (Qt5 like KeePassXC, and Qt6) use `qt5ct`/`qt6ct` as their platform theme (`QT_QPA_PLATFORMTHEME=qt6ct`) instead of Omarchy's `gtk3`, which draws GTK3 dialogs in-process: their `standard_dialogs=xdgdesktopportal` option asks the portal, and they also set the Qt UI font to GTK's family at `omarchy_system_ui_font_pt` (Qt's plain `xdgdesktopportal` theme would give portal dialogs but a 9pt fallback font). Log out and back in (or restart the app) to pick it up. |
| LazyVim plugins | `lazyvim` | Enables LazyVim's LaTeX extra and installs [gregorio.nvim](https://github.com/AISCGre-BR/gregorio.nvim) (GABC/NABC chant notation, pairs with gregorio-lsp). |
| Gregorio | `gregorio` | Builds and installs the Gregorio GABC → GregorioTeX engraver from source. Depends on TeX Live (its tag also runs the TeX Live play first). Not part of `just setup`. |
| pt-BR localization | `ptbr` | Locale, personal folder names, Firefox/Chromium/LibreOffice/man pages/OCR language. |
| Podman | `podman` | Rootless container engine. Part of `playbooks/containers.yml` with Distrobox and the starship integration (umbrella tag `containers`). |
| Distrobox | `distrobox` | Depends on Podman: the tag also runs the Podman play first. |
| Flatpak + Flathub | `flatpak` | Installs Flatpak and enables the Flathub remote (per-user, so app installs don't need root). |
| Homebrew | `homebrew` | Installs Homebrew for Linux to `/home/linuxbrew/.linuxbrew` and symlinks `brew` into `/usr/local/bin`. |
| snapd | `snapd` | Builds and installs snapd from the AUR (no official Arch package), enables `snapd.socket` (+ `snapd.apparmor.service`), links `/snap` → `/var/lib/snapd/snap` (classic snaps expect it), waits for first-boot seeding, and exports snap's `bin` and desktop-entry dirs to the graphical session (`PATH`/`XDG_DATA_DIRS` via `environment.d`; log out and back in to pick it up). Doesn't touch the kernel cmdline: strict confinement would need AppArmor as the active LSM, which Omarchy doesn't enable by default — snapd still works, and classic snaps don't need it. |
| Visual Studio Code | `vscode` | Installs VS Code from Microsoft's official snap (`--classic`). Depends on `snapd` (the tag also runs the snapd play first; `playbooks/snap.yml`, umbrella tag `snap`). Also fixes two Hyprland issues: sets `"password-store": "gnome-libsecret"` in `~/.vscode/argv.json` so VS Code uses the Secret Service keyring (Electron doesn't detect one under Hyprland), and installs a `~/.local/bin/code` wrapper + user desktop entries that set the UI scale to the monitor scale (the snap is forced onto XWayland, where `GDK_SCALE=2` made the UI too big). |
| libfprint (goodix538d) | `libfprint` | Builds and installs a fingerprint driver fork, plus a watchdog for a driver desync bug and the Omarchy lock-screen retry-storm bug. |
| EPSON L4160 printer | `printer` | Driverless CUPS queue (IPP Everywhere). |
| Hyprland scrolling resize | `hypr-scrolling-resize` | SUPER+[ / SUPER+] resize the focused column. This and the next two are plays of `playbooks/desktop.yml` (umbrella tag `desktop`). |
| Screen scale + text size | `text-size` | Sets the Hyprland monitor scale to 100% (and `GDK_SCALE` to match) and compensates with larger text: shell bar + terminals at 20px (15pt terminal font) and the GTK UI font at 12pt (Qt follows it through the `file-chooser` play), with GTK's text-scaling factor left at 1.0. |
| Night light | `nightlight-solar` | Syncs hyprsunset to real sunrise/sunset daily. |
| Caps Lock via keyd | `capslock` | tap=Esc, hold=Ctrl, Shift+CapsLock=CapsLock; moves Compose off Caps Lock. |
| Inkscape + svg2tikz | `inkscape` | Installs Inkscape and the [svg2tikz](https://github.com/xyz2tex/svg2tikz) extension (AUR `python-svg2tikz`) for exporting SVG paths as TikZ/PGF code for LaTeX. Also points fontconfig at TeX Live's own fonts, so Latin Modern and other TeX families show up in Inkscape's (and every fontconfig app's) font picker. |
| Omadwaita themes | `omadwaita-themes` | Installs three Adwaita-based Omarchy themes whose terminal palettes come from Adwaita's nine accent colors, WCAG-AA-checked on their background: **Omadwaita** (dark TUI, light GTK — a `theme-set` hook flips GTK back to light), **Omadwaita Light** and **Omadwaita Dark**. All three use the Adwaita icon theme and share one wallpaper set (devotional paintings and wallpapers, `playbooks/files/omadwaita/backgrounds/`, migrated from the former Sacred Heart theme), plus a generated fallback wallpaper (the Omarchy logo on a gradient in the theme's palette). Browsers (Chromium, Brave, Chrome, Edge) get a per-theme `chromium.theme` seed color so their accent has Adwaita blue's hue instead of an arbitrary one derived from the neutral background. Omarchy never recolors GTK (it only picks `Adwaita`/`Adwaita-dark` from the theme's `mode`), so GTK apps keep the stock Adwaita palette. Installs only; apply with `omarchy-theme-set "Omadwaita"`. |
| Limine silent boot | `limine-silent-boot` | Sets `quiet: yes` (in the config header, before the first entry — otherwise Limine ignores it) and `timeout: 1` in `/boot/limine.conf` (and removes any `firmware_logo`) for a flicker-free boot: with `quiet` in effect Limine draws nothing and keeps the firmware BGRT logo on screen through its 1-second key window (press ↑/↓ to reveal the menu — not Space/Enter, which Limine treats as "boot the selected entry"; snapshots/fallback stay reachable). Re-runs `limine-update` to re-enroll the config checksum, so it also works with Secure Boot's `ENABLE_ENROLL_LIMINE_CONFIG=yes`. |
| ble.sh | `blesh` | Loads [ble.sh](https://github.com/akinomyoga/ble.sh) by default in Bash — Omarchy doesn't — with fish-style **autosuggestions** (ghost text from history, then completion) and **syntax highlighting** as you type. Builds AUR `blesh-git` (0.4.0-devel: the stable 0.3.4 predates Bash 5.3 and warns on every shell start against Omarchy's inputrc). Wraps the `source "$OMARCHY_PATH/default/bash/rc"` line in `~/.bashrc` with `source ble.sh --noattach` before it and `ble-attach` at the end, so starship and fzf's key bindings (Ctrl-R etc.) keep working; the feature options live in `~/.blerc`. Open a new terminal to pick it up. |
| Starship in distrobox | `starship-distrobox` | Makes the prompt work inside distrobox containers and show which one you're in (`⬢ <container> <dir> <branch> ❯`). Omarchy's `~/.bashrc` sources `$OMARCHY_PATH/default/bash/rc`, which doesn't exist in the container (its `/usr` is the image's; the host's is at `/run/host`), so starship never started: a `~/.bashrc` block points `OMARCHY_PATH` at `/run/host` inside distrobox and falls back to the host's starship binary (same Arch userland; another distro may need its own). The name comes from `CONTAINER_ID`, exported by `distrobox-enter`, through starship's `env_var` module in `~/.config/starship.toml` (blank on the host). |
| TeX Live | `texlive` | Installs TeX Live via AUR `texlive-installer` (scheme-minimal + AISCGre-BR package selection). Not part of `just setup` — a long network install, run explicitly. Shares `playbooks/tex.yml` with Gregorio (umbrella tag `tex`). |
| AppArmor | — | Activates AppArmor as a kernel LSM: `lsm=landlock,lockdown,yama,integrity,apparmor,bpf` (the kernel is built with it but leaves it out of the default list) via a `limine-entry-tool` drop-in + `limine-update`; needs a reboot. Two variants: **`just apparmor`** (kernel LSM only — no distro profiles loaded, the desktop is unchanged, snapd still confines strict snaps with its own profiles) and **`just apparmor-profiles`** (also enables `apparmor.service`, loading `/etc/apparmor.d`; on this setup that enforces `unix-chkpwd`, `avahi-daemon`, `ping`, …). Not part of `just setup`. |
| BGRT boot theme | `bgrt-theme` | Builds an Omarchy theme + a standalone Plymouth theme from this machine's own UEFI BGRT boot logo, so the same picture stays on screen from firmware through Plymouth to Hyprlock. Not part of `just setup` — rewrites the default Plymouth theme and rebuilds the initramfs. |
| Secure Boot | `secureboot` | Limine + sbctl. Not part of `just setup` — see [`docs/secureboot.md`](docs/secureboot.md). |
| Yubikey GPG key | `gpg-yubikey` | Imports the public key, trusts it, configures git signing. Not part of `just setup`. Shares `playbooks/yubikey.yml` with the SSH keys (umbrella tag `yubikey`). |
| Yubikey SSH keys | `ssh-yubikey` | Prepares for downloading resident FIDO2 keys. Not part of `just setup`. |

See each playbook's own header comment for implementation details.

## Prerequisites

- An Omarchy desktop (or any Arch Linux with pacman, `locale-gen`,
  systemd and `xdg-user-dirs`).
- `run0` (part of systemd, so already there on Arch) and a user in the
  `wheel` group.
- The libfprint playbook needs Podman + Distrobox already set up
  (`site.yml` already runs them in the right order).
- The Proton Pass playbook needs Flatpak + Flathub (desktop client) and
  Homebrew (CLI) already set up (`site.yml` already runs both in the
  right order).
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

```bash
git clone https://github.com/lbssousa/omarchy-setup.git
cd omarchy-setup
./bootstrap.sh   # installs `just`, if missing — only needs to run once
just setup
```

Or directly with Ansible:

```bash
run0 pacman -S --needed ansible
ansible-galaxy collection install -r requirements.yml
./run-empowered.sh ansible-playbook site.yml
```

Run a single automation with `just <name>` (see the Justfile) or
`./run-empowered.sh ansible-playbook site.yml --tags <tag>`.

The playbooks are idempotent — rerunning is safe.

**KeePassXC, Bitwarden, Proton Pass, TeX Live, Gregorio, the BGRT boot theme,
AppArmor, Secure Boot, the Yubikey GPG key, and the Yubikey SSH keys are
separate** — not part of `just setup`:

```bash
just keepassxc     # one of three alternative password managers — pick any
just bitwarden     # combination, or none; no password manager is the default
just proton-pass   # desktop client (AUR) + CLI (official installer)
just proton-pass-cli  # just the CLI, no root needed
just texlive       # TeX Live is a long network install; run when you need it
just gregorio      # also runs the TeX Live play first; builds the Gregorio engraver
just bgrt-theme    # builds the BGRT-derived boot theme; needs a firmware BGRT logo
just apparmor      # AppArmor as a kernel LSM, no distro profiles; needs a reboot
just apparmor-profiles  # same + apparmor.service loading /etc/apparmor.d's profiles
just secureboot    # see docs/secureboot.md for the full walkthrough
just gpg-yubikey   # needs the Yubikey plugged in
just ssh-yubikey   # needs the Yubikey plugged in
just brave-pwa-webapps  # needs root; each container must already exist in Brave
```

## Structure

| File/Directory | Role |
|---|---|
| `bootstrap.sh` | Installs `just`, if missing |
| `run-empowered.sh` | Runs ansible-playbook under `run0 --empower`: one polkit authentication, then privileged tasks pass (see *Privilege* above) |
| `site.yml` | Index: imports each `playbooks/*.yml` with its tag |
| `playbooks/polkit.yml` | polkitd ExpirationSeconds + legacy cleanup (sudoers drop-in, OpenSSH agent no longer enabled by default) (tag `polkit`) |
| `playbooks/firefox.yml` | Firefox + tab apps (tag `firefox`) |
| `playbooks/brave-pwa-webapps.yml` | Swap Omarchy preinstalled web apps for Brave PWAs opening in their own container — outside `site.yml` (tag `brave-pwa-webapps`) |
| `playbooks/zed.yml` | Zed editor + Omarchy theme + font size (tag `zed`) |
| `playbooks/gregorio-lsp.yml` | gregorio-lsp, grelint, grefmt, built from source (tag `gregorio-lsp`) |
| `playbooks/pdf-viewer.yml` | Zathura default + Papers optional, Evince kept for sushi (tag `pdf-viewer`) |
| `playbooks/pinentry.yml` | pinentry-omarchy package, shell plugin, gpg-agent `pinentry-program` (tag `pinentry`) |
| `playbooks/lazyvim.yml` | LazyVim LaTeX extra + gregorio.nvim (tag `lazyvim`) |
| `playbooks/ptbr.yml` | pt-BR localization (tag `ptbr`) |
| `playbooks/keepassxc.yml` | OpenSSH agent (tag `ssh-agent`) + KeePassXC + Qt5 Wayland plugin + XDG autostart — optional password manager, outside `site.yml` (tag `keepassxc`) |
| `playbooks/bitwarden.yml` | Bitwarden — optional password manager, outside `site.yml` (tag `bitwarden`) |
| `playbooks/proton-pass.yml` | Proton Pass desktop (Flatpak, `me.proton.Pass`) + CLI (Homebrew, `proton-pass-cli`), with the CLI's own SSH agent (`pass-cli ssh-agent`) wired to `SSH_AUTH_SOCK` via a systemd --user service — optional password manager, outside `site.yml` (tags `proton-pass-desktop`, `proton-pass-cli`; umbrella `proton-pass`) |
| `playbooks/containers.yml` | Podman rootless, Distrobox, starship prompt inside distrobox (tags `podman`, `distrobox`, `starship-distrobox`; umbrella `containers`) |
| `playbooks/flatpak.yml` | Flatpak + Flathub remote (tag `flatpak`) |
| `playbooks/snap.yml` | snapd from the AUR (`/snap` link + session env) and Visual Studio Code's official snap + keyring/UI-scale fixes (tags `snapd`, `vscode`; umbrella `snap`) |
| `playbooks/libfprint.yml` | libfprint goodix538d (tag `libfprint`) |
| `playbooks/printer.yml` | EPSON L4160 printer (tag `printer`) |
| `playbooks/desktop.yml` | Scrolling-layout column resize, screen scale (100%) + text size, night light synced to sunrise/sunset (tags `hypr-scrolling-resize`, `text-size`, `nightlight-solar`; umbrella `desktop`) |
| `playbooks/capslock.yml` | Caps Lock via keyd (tag `capslock`) |
| `playbooks/omadwaita-themes.yml` | Omadwaita / Omadwaita Light / Omadwaita Dark Omarchy themes (tag `omadwaita-themes`) |
| `playbooks/limine-silent-boot.yml` | Limine silent boot — quiet (header-only) + `timeout: 1`, re-enrolls config checksum (tag `limine-silent-boot`) |
| `playbooks/blesh.yml` | ble.sh in Bash: autosuggestions + syntax highlighting, wired into `~/.bashrc` / `~/.blerc` (tag `blesh`) |
| `playbooks/tex.yml` | TeX Live via AUR texlive-installer + Gregorio engraver built from source — outside `site.yml` (tags `texlive`, `gregorio`; umbrella `tex`) |
| `playbooks/apparmor.yml` | AppArmor kernel LSM (+ optional distro profiles) — outside `site.yml` (`just apparmor` / `just apparmor-profiles`) |
| `playbooks/bgrt-theme.yml` | BGRT-derived boot theme — outside `site.yml` (tag `bgrt-theme`) |
| `playbooks/secureboot.yml` | Secure Boot — outside `site.yml` (tag `secureboot`) |
| `docs/secureboot.md` | `just secureboot` walkthrough |
| `playbooks/yubikey.yml` | Yubikey GPG key + resident SSH keys — outside `site.yml` (tags `gpg-yubikey`, `ssh-yubikey`; umbrella `yubikey`) |
| `playbooks/files/` | Static files copied as-is |
| `playbooks/templates/` | Jinja2 templates |
| `playbooks/tasks/` | Reusable tasks included via `include_tasks` |
| `group_vars/all/main.yml` | Variables for all automations |
| `requirements.yml` | Required Ansible collections |
| `Justfile` | Shortcuts (`just setup`, `just ptbr`, etc.) |
