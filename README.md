# omarchy-setup

Ansible automation for setting up a freshly installed
[Omarchy](https://omarchy.org/) desktop.

Each automation is its own playbook under `playbooks/`, imported by
`site.yml`. All of them share the same privilege escalation (sudo, see
`ansible.cfg`), and each has its own tag: run one with `--tags <tag>`,
or skip one with `--skip-tags <tag>`. Exceptions:
`playbooks/secureboot.yml`, `playbooks/bgrt-theme.yml`,
`playbooks/apparmor.yml`, `playbooks/bitwarden.yml`,
`playbooks/texlive.yml` and `playbooks/gregorio.yml` are **not**
imported by `site.yml` — Secure Boot, the BGRT boot theme and AppArmor
touch firmware/boot, Bitwarden is an
optional alternative to the default KeePassXC, and TeX Live (+ Gregorio,
which depends on it) is a long download/install you run on demand — so
they only run when called explicitly.

## What it sets up

| Automation | Tag | What it does |
|---|---|---|
| Firefox | `firefox` | Installs Firefox and enables tab apps (Taskbar Tabs), off by default on Linux. Runs before pt-BR localization. |
| Zed editor | `zed` | Installs Zed + omazed (Omarchy theme integration), sets every font size (UI, buffer, agent, terminal) to 20px and the buffer font to JetBrainsMono Nerd Font, and sets `use_podman` so Dev Containers use Podman instead of Docker. |
| gregorio-lsp | `gregorio-lsp` | Installs Rust (`omarchy install dev-env rust`) if needed, then builds and installs the `gregorio-lsp`, `grelint` and `grefmt` binaries from source. |
| PDF viewer | `pdf-viewer` | Installs Zathura (+ MuPDF backend) as the default PDF viewer and Papers as an extra, non-default viewer. Evince stays installed since Nautilus's sushi previewer depends on it. |
| LazyVim plugins | `lazyvim` | Enables LazyVim's LaTeX extra and installs [gregorio.nvim](https://github.com/AISCGre-BR/gregorio.nvim) (GABC/NABC chant notation, pairs with gregorio-lsp). |
| Gregorio | `gregorio` | Builds and installs the Gregorio GABC → GregorioTeX engraver from source. Depends on TeX Live (runs `just texlive` first). Not part of `just setup`. |
| pt-BR localization | `ptbr` | Locale, personal folder names, Firefox/Chromium/LibreOffice/man pages/OCR language. |
| OpenSSH agent | `ssh-agent` | Enables the systemd --user ssh-agent at the session socket + exports `SSH_AUTH_SOCK` session-wide. Runs before KeePassXC. |
| KeePassXC | `keepassxc` | Default password manager: desktop client (native Wayland via `qt5-wayland`) + browser integration (Firefox/Chromium/Brave) + SSH agent support (via `ssh-agent`) + monochrome tray icon (minimize/close to tray) + session autostart. |
| Podman | `podman` | Rootless container engine. |
| Distrobox | `distrobox` | Depends on Podman. |
| Flatpak + Flathub | `flatpak` | Installs Flatpak and enables the Flathub remote (per-user, so app installs don't need root). |
| Homebrew | `homebrew` | Installs Homebrew for Linux to `/home/linuxbrew/.linuxbrew` and symlinks `brew` into `/usr/local/bin`. |
| snapd | `snapd` | Builds and installs snapd from the AUR (no official Arch package), enables `snapd.socket` (+ `snapd.apparmor.service`), links `/snap` → `/var/lib/snapd/snap` (classic snaps expect it), waits for first-boot seeding, and exports snap's `bin` and desktop-entry dirs to the graphical session (`PATH`/`XDG_DATA_DIRS` via `environment.d`; log out and back in to pick it up). Doesn't touch the kernel cmdline: strict confinement would need AppArmor as the active LSM, which Omarchy doesn't enable by default — snapd still works, and classic snaps don't need it. |
| Visual Studio Code | `vscode` | Installs VS Code from Microsoft's official snap (`--classic`). Depends on `snapd` (fails early with guidance if it's missing). |
| libfprint (goodix538d) | `libfprint` | Builds and installs a fingerprint driver fork, plus a watchdog for a driver desync bug and the Omarchy lock-screen retry-storm bug. |
| EPSON L4160 printer | `printer` | Driverless CUPS queue (IPP Everywhere). |
| Hyprland scrolling resize | `hypr-scrolling-resize` | SUPER+[ / SUPER+SHIFT+[ resize the focused column. |
| Shell/terminal text size | `text-size` | Scales the bar + terminals without scaling GTK apps. |
| Night light | `nightlight-solar` | Syncs hyprsunset to real sunrise/sunset daily. |
| Caps Lock via keyd | `capslock` | tap=Esc, hold=Ctrl, Shift+CapsLock=CapsLock; moves Compose off Caps Lock. |
| Inkscape + svg2tikz | `inkscape` | Installs Inkscape and the [svg2tikz](https://github.com/xyz2tex/svg2tikz) extension (AUR `python-svg2tikz`) for exporting SVG paths as TikZ/PGF code for LaTeX. Also points fontconfig at TeX Live's own fonts, so Latin Modern and other TeX families show up in Inkscape's (and every fontconfig app's) font picker. |
| Omadwaita themes | `omadwaita-themes` | Installs three Adwaita-based Omarchy themes whose terminal palettes come from Adwaita's nine accent colors, WCAG-AA-checked on their background: **Omadwaita** (dark TUI, light GTK — a `theme-set` hook flips GTK back to light), **Omadwaita Light** and **Omadwaita Dark**. All three use the Adwaita icon theme and share one wallpaper set (devotional paintings and wallpapers, `playbooks/files/omadwaita/backgrounds/`, migrated from the former Sacred Heart theme), plus a generated fallback wallpaper (the Omarchy logo on a gradient in the theme's palette). Omarchy never recolors GTK (it only picks `Adwaita`/`Adwaita-dark` from the theme's `mode`), so GTK apps keep the stock Adwaita palette. Installs only; apply with `omarchy-theme-set "Omadwaita"`. |
| Limine silent boot | `limine-silent-boot` | Sets `quiet: yes` (in the config header, before the first entry — otherwise Limine ignores it) and `timeout: 1` in `/boot/limine.conf` (and removes any `firmware_logo`) for a flicker-free boot: with `quiet` in effect Limine draws nothing and keeps the firmware BGRT logo on screen through its 1-second key window (press ↑/↓ to reveal the menu — not Space/Enter, which Limine treats as "boot the selected entry"; snapshots/fallback stay reachable). Re-runs `limine-update` to re-enroll the config checksum, so it also works with Secure Boot's `ENABLE_ENROLL_LIMINE_CONFIG=yes`. |
| ble.sh | `blesh` | Loads [ble.sh](https://github.com/akinomyoga/ble.sh) by default in Bash — Omarchy doesn't — with fish-style **autosuggestions** (ghost text from history, then completion) and **syntax highlighting** as you type. Builds AUR `blesh-git` (0.4.0-devel: the stable 0.3.4 predates Bash 5.3 and warns on every shell start against Omarchy's inputrc). Wraps the `source "$OMARCHY_PATH/default/bash/rc"` line in `~/.bashrc` with `source ble.sh --noattach` before it and `ble-attach` at the end, so starship and fzf's key bindings (Ctrl-R etc.) keep working; the feature options live in `~/.blerc`. Open a new terminal to pick it up. |
| TeX Live | `texlive` | Installs TeX Live via AUR `texlive-installer` (scheme-minimal + AISCGre-BR package selection). Not part of `just setup` — a long network install, run explicitly. |
| AppArmor | — | Activates AppArmor as a kernel LSM: `lsm=landlock,lockdown,yama,integrity,apparmor,bpf` (the kernel is built with it but leaves it out of the default list) via a `limine-entry-tool` drop-in + `limine-update`; needs a reboot. Two variants: **`just apparmor`** (kernel LSM only — no distro profiles loaded, the desktop is unchanged, snapd still confines strict snaps with its own profiles) and **`just apparmor-profiles`** (also enables `apparmor.service`, loading `/etc/apparmor.d`; on this setup that enforces `unix-chkpwd`, `avahi-daemon`, `ping`, …). Not part of `just setup`. |
| BGRT boot theme | `bgrt-theme` | Builds an Omarchy theme + a standalone Plymouth theme from this machine's own UEFI BGRT boot logo, so the same picture stays on screen from firmware through Plymouth to Hyprlock. Not part of `just setup` — rewrites the default Plymouth theme and rebuilds the initramfs. |
| Secure Boot | `secureboot` | Limine + sbctl. Not part of `just setup` — see [`docs/secureboot.md`](docs/secureboot.md). |
| Yubikey GPG key | `gpg-yubikey` | Imports the public key, trusts it, configures git signing. Not part of `just setup`. |
| Yubikey SSH keys | `ssh-yubikey` | Prepares for downloading resident FIDO2 keys. Not part of `just setup`. |

See each playbook's own header comment for implementation details.

## Prerequisites

- An Omarchy desktop (or any Arch Linux with pacman, `locale-gen`,
  systemd and `xdg-user-dirs`).
- `sudo` and a user in the `wheel` group.
- The libfprint playbook needs Podman + Distrobox already set up
  (`site.yml` already runs them in the right order).
- The Secure Boot playbook only covers Limine + limine-entry-tool.

Neither `just` nor `ansible` need to be pre-installed: `./bootstrap.sh`
installs `just`; `just setup` then installs `ansible` and the
`community.general` collection on its own.

### Privilege: sudo + --ask-become-pass

Every privileged task uses sudo with `--ask-become-pass`: it asks for
your password once, at the start, and feeds it to sudo whenever needed.

That password is a fallback, not the primary method: the fingerprint
reader is configured as a sudo login method outside this repo, and is
tried first on every privileged task, silently. If it doesn't resolve,
the password covers the rest. `ansible_local_become_success_timeout: 60`
(in `group_vars/all/main.yml`) gives the fingerprint prompt enough time
to give up on its own before Ansible's local connection times out
waiting for it.

Careful with hidden/unattended terminals: the fingerprint prompt is
still tried first even with nobody there to touch the sensor. A caller
without a human present should use `ansible_become_flags=-H -n` (or
`sudo -n`) to fail fast instead. As a safety net,
[`playbooks/sudo.yml`](playbooks/sudo.yml) lowers sudo's
`passwd_timeout` to limit how long that can hang.

## Usage

```bash
git clone https://github.com/lbssousa/omarchy-setup.git
cd omarchy-setup
./bootstrap.sh   # installs `just`, if missing — only needs to run once
just setup
```

Or directly with Ansible:

```bash
sudo pacman -S --needed ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook site.yml --ask-become-pass
```

Run a single automation with `just <name>` (see the Justfile) or
`ansible-playbook site.yml --ask-become-pass --tags <tag>`.

The playbooks are idempotent — rerunning is safe.

**Bitwarden, TeX Live, Gregorio, the BGRT boot theme, AppArmor, Secure Boot, the
Yubikey GPG key, and the Yubikey SSH keys are separate** — not part of
`just setup`:

```bash
just bitwarden     # optional; KeePassXC is the default password manager
just texlive       # TeX Live is a long network install; run when you need it
just gregorio      # runs `just texlive` first; builds the Gregorio engraver
just bgrt-theme    # builds the BGRT-derived boot theme; needs a firmware BGRT logo
just apparmor      # AppArmor as a kernel LSM, no distro profiles; needs a reboot
just apparmor-profiles  # same + apparmor.service loading /etc/apparmor.d's profiles
just secureboot    # see docs/secureboot.md for the full walkthrough
just gpg-yubikey   # needs the Yubikey plugged in
just ssh-yubikey   # needs the Yubikey plugged in
```

## Structure

| File/Directory | Role |
|---|---|
| `bootstrap.sh` | Installs `just`, if missing |
| `site.yml` | Index: imports each `playbooks/*.yml` with its tag |
| `playbooks/sudo.yml` | sudo passwd_timeout (tag `sudo`) |
| `playbooks/polkit.yml` | polkitd ExpirationSeconds (tag `polkit`) |
| `playbooks/firefox.yml` | Firefox + tab apps (tag `firefox`) |
| `playbooks/zed.yml` | Zed editor + Omarchy theme + font size (tag `zed`) |
| `playbooks/gregorio-lsp.yml` | gregorio-lsp, grelint, grefmt, built from source (tag `gregorio-lsp`) |
| `playbooks/pdf-viewer.yml` | Zathura default + Papers optional, Evince kept for sushi (tag `pdf-viewer`) |
| `playbooks/lazyvim.yml` | LazyVim LaTeX extra + gregorio.nvim (tag `lazyvim`) |
| `playbooks/ptbr.yml` | pt-BR localization (tag `ptbr`) |
| `playbooks/ssh-agent.yml` | OpenSSH agent, user session (tag `ssh-agent`) |
| `playbooks/keepassxc.yml` | KeePassXC + Qt5 Wayland plugin + XDG autostart (tag `keepassxc`) |
| `playbooks/bitwarden.yml` | Bitwarden — optional, outside `site.yml` (tag `bitwarden`) |
| `playbooks/podman.yml` | Podman rootless (tag `podman`) |
| `playbooks/distrobox.yml` | Distrobox (tag `distrobox`) |
| `playbooks/flatpak.yml` | Flatpak + Flathub remote (tag `flatpak`) |
| `playbooks/homebrew.yml` | Homebrew for Linux (tag `homebrew`) |
| `playbooks/snapd.yml` | snapd from the AUR, enabled + `/snap` link + session env (tag `snapd`) |
| `playbooks/vscode.yml` | Visual Studio Code, official snap (tag `vscode`) |
| `playbooks/libfprint.yml` | libfprint goodix538d (tag `libfprint`) |
| `playbooks/printer.yml` | EPSON L4160 printer (tag `printer`) |
| `playbooks/hypr-scrolling-resize.yml` | Scrolling-layout column resize (tag `hypr-scrolling-resize`) |
| `playbooks/text-size.yml` | Shell bar + terminal text size (tag `text-size`) |
| `playbooks/nightlight-solar.yml` | Night light synced to sunrise/sunset (tag `nightlight-solar`) |
| `playbooks/capslock.yml` | Caps Lock via keyd (tag `capslock`) |
| `playbooks/omadwaita-themes.yml` | Omadwaita / Omadwaita Light / Omadwaita Dark Omarchy themes (tag `omadwaita-themes`) |
| `playbooks/limine-silent-boot.yml` | Limine silent boot — quiet (header-only) + `timeout: 1`, re-enrolls config checksum (tag `limine-silent-boot`) |
| `playbooks/blesh.yml` | ble.sh in Bash: autosuggestions + syntax highlighting, wired into `~/.bashrc` / `~/.blerc` (tag `blesh`) |
| `playbooks/texlive.yml` | TeX Live via AUR texlive-installer — outside `site.yml` (tag `texlive`) |
| `playbooks/gregorio.yml` | Gregorio engraver, builds from source — outside `site.yml` (tag `gregorio`) |
| `playbooks/apparmor.yml` | AppArmor kernel LSM (+ optional distro profiles) — outside `site.yml` (`just apparmor` / `just apparmor-profiles`) |
| `playbooks/bgrt-theme.yml` | BGRT-derived boot theme — outside `site.yml` (tag `bgrt-theme`) |
| `playbooks/secureboot.yml` | Secure Boot — outside `site.yml` (tag `secureboot`) |
| `docs/secureboot.md` | `just secureboot` walkthrough |
| `playbooks/yubikey-gpg.yml` | Yubikey GPG key — outside `site.yml` (tag `gpg-yubikey`) |
| `playbooks/yubikey-ssh.yml` | Yubikey resident SSH keys — outside `site.yml` (tag `ssh-yubikey`) |
| `playbooks/files/` | Static files copied as-is |
| `playbooks/templates/` | Jinja2 templates |
| `playbooks/tasks/` | Reusable tasks included via `include_tasks` |
| `group_vars/all/main.yml` | Variables for all automations |
| `requirements.yml` | Required Ansible collections |
| `Justfile` | Shortcuts (`just setup`, `just ptbr`, etc.) |
