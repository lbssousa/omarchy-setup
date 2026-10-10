set shell := ["bash", "-uc"]

# Playbooks that need root run under `run0 --empower` (see run-empowered.sh):
# one polkit authentication up front, then every `become: true` task's run0
# inside passes without prompting again. Recipes for user-level-only tags
# call plain ansible-playbook.
ap := "./run-empowered.sh ansible-playbook"

default:
    @just --list

# Install ansible via pacman if it isn't already on PATH.
_ensure-ansible:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v ansible-playbook >/dev/null; then
        echo "ansible-playbook not found; installing via pacman..."
        run0 pacman -S --needed --noconfirm ansible
    fi

# Install collections required by the playbooks (community.general).
_ensure-collections: _ensure-ansible
    ansible-galaxy collection install -r requirements.yml

# Run every automation. Authenticate once, in the polkit dialog that appears
# at the start (fingerprint or password).
setup: _ensure-collections
    {{ap}} site.yml

# Raise polkitd's authentication cache window and remove the legacy sudoers
# drop-in an older version of this repo installed.
polkit: _ensure-collections
    {{ap}} site.yml --tags polkit

# Install Firefox from Flathub and turn tab apps (Taskbar Tabs) on by
# default.
firefox: _ensure-collections
    {{ap}} site.yml --tags firefox

# Install Brave from Flathub, remove the AUR brave-origin-bin package,
# and fix up Brave's Flatpak PWA .desktop files (also runs on its own —
# see brave-pwa-desktop-fix below) plus Omarchy's web app container
# wiring (see brave-webapp-containers below).
brave: _ensure-collections
    {{ap}} site.yml --tags brave

# Rerun just the Brave Flatpak PWA .desktop fixup (also installs the
# systemd --user watcher that reruns it automatically). No root needed.
brave-pwa-desktop-fix: _ensure-collections
    ansible-playbook site.yml --tags brave-pwa-desktop-fix

# Rerun just the Omarchy web app -> Brave container wiring (also installs
# the systemd --user watcher that reruns it when the launchers change).
# Launchers listed in brave_omarchy_webapp_containers get a trailing
# --container=<name> on their Exec=, so they open inside that Brave
# container. No root needed.
brave-webapp-containers: _ensure-collections
    ansible-playbook site.yml --tags brave-webapp-containers

# Rebind the YouTube/WhatsApp/Microsoft Teams keys to the sites pinned to the
# Firefox taskbar (the tab apps themselves are pinned by hand in Firefox).
# No root needed.
firefox-pwa-keybinds: _ensure-collections
    ansible-playbook site.yml --tags firefox-pwa-keybinds

# Make the Flathub Brave the default browser (unless it already is), via a
# brave-browser.desktop shim so Omarchy's native web apps run on it, and
# deploy omarchy-setup-default-browser, a Flathub-aware alternative to
# `omarchy default browser` for Firefox/Brave. No root needed.
default-browser: _ensure-collections
    ansible-playbook site.yml --tags default-browser

# Install LibreOffice from Flathub, remove the pre-installed native
# libreoffice-fresh (+ its pt-BR language pack), and re-curate the app
# launcher/keybinds to match.
libreoffice: _ensure-collections
    {{ap}} site.yml --tags libreoffice

# Install Zed (Omarchy theme integration), set every font size to 25px
# and the buffer font to JetBrainsMono Nerd Font.
zed: _ensure-collections
    {{ap}} site.yml --tags zed

# Replace the native Kdenlive/OBS Studio/Pinta/Xournal++ that Omarchy
# pre-installs with their Flathub builds (see
# docs/flathub-migration-survey.md). Edit flathub_app_migrations in
# group_vars/all/main.yml to migrate a subset.
flathub-apps: _ensure-collections
    {{ap}} site.yml --tags flathub-apps

# Install Rust (if needed) and build/install gregorio-lsp, grelint and
# grefmt from source.
gregorio-lsp: _ensure-collections
    ansible-playbook site.yml --tags gregorio-lsp

# Make Zathura (Flathub) the default PDF viewer + Papers (optional
# viewer); Evince stays installed (sushi depends on it). Replaces the
# native zathura + zathura-pdf-mupdf pair — note the Flatpak bundles the
# poppler backend instead, and only grants ~/Documents + ~/Downloads
# (see pdf_viewer_zathura_extra_paths in group_vars/all/main.yml).
pdf-viewer: _ensure-collections
    {{ap}} site.yml --tags pdf-viewer

# Build/install pinentry-omarchy (GnuPG prompts in the polkit-style shell
# dialog) and make gpg-agent use it. Run from inside the graphical session.
# Needs the Yubikey's GPG key in the keyring (`just gpg-yubikey` first).
pinentry: _ensure-collections
    {{ap}} site.yml --tags pinentry

# Build/install ssh-askpass-omarchy (SSH prompts in the polkit-style shell
# dialog) and configure SSH to use it. Run from inside the graphical session.
# Needs the Yubikey's GPG key in the keyring (`just gpg-yubikey` first).
ssh-askpass: _ensure-collections
    {{ap}} site.yml --tags ssh-askpass

# Rebuild Arch's openssh with the patch that sends security key touch
# requests to SSH_ASKPASS when ssh runs in a terminal. Re-run after each
# openssh update from the repos.
openssh-askpass: _ensure-collections
    {{ap}} site.yml --tags openssh-askpass

# Replace Omarchy's polkit agent with polkit-omarchy (touch prompt for
# pam_u2f security keys). Run from inside the graphical session.
# Needs the Yubikey's GPG key in the keyring (`just gpg-yubikey` first).
polkit-agent: _ensure-collections
    {{ap}} site.yml --tags polkit-agent

# Install the list of third-party shell plugins in omarchy_plugins
# (group_vars/all/main.yml) — Radio Atlas first — cloned by
# `omarchy plugin add`, pinned to each entry's ref, and placed in the bar
# section the entry asks for. Run from inside the graphical session; root is
# only needed if one of the plugins' runtime dependencies is missing.
plugins: _ensure-collections
    {{ap}} site.yml --tags plugins

# Make the open/save file dialogs of non-GNOME apps the GTK4 ones (xdg-desktop-portal-gnome).
file-chooser: _ensure-collections
    {{ap}} site.yml --tags file-chooser

# Enable LazyVim's LaTeX extra and install gregorio.nvim (GABC/NABC).
lazyvim: _ensure-collections
    ansible-playbook site.yml --tags lazyvim

# Install TeX Live, LilyPond and Gregorio directly on this machine (no
# containers, no Ansible) — see local-typesetting/README.md. A long
# network install; not part of `just setup`. Needs sudo.
typesetting:
    ./local-typesetting/install-typesetting.sh

# Run only the pt-BR localization playbook.
ptbr: _ensure-collections
    {{ap}} site.yml --tags ptbr

# Run only the OpenSSH agent (user session) play, opting in to it
# (keepassxc_ssh_agent_enabled is false by default, so `just keepassxc`
# leaves the agent off). Part of playbooks/keepassxc.yml (optional, not
# part of `just setup`). No root needed.
ssh-agent: _ensure-collections
    ansible-playbook playbooks/keepassxc.yml --tags ssh-agent -e keepassxc_ssh_agent_enabled=true

# Run the KeePassXC playbook. Installs KeePassXC from Flathub and removes
# the native package. Optional password manager alternative, not part of
# `just setup`. The SSH agent stays off; add
# -e keepassxc_ssh_agent_enabled=true here (or run `just ssh-agent`) to have
# KeePassXC act as a client for it as well.
keepassxc: _ensure-collections
    {{ap}} playbooks/keepassxc.yml

# Create the rclone config + systemd --user mounts for Google Drive. Needs
# RCLONE_GDRIVE_CLIENT_ID and RCLONE_GDRIVE_CLIENT_SECRET in the environment on
# the first run (reused from rclone.conf afterwards). Not part of `just setup`;
# only the package install needs root.
rclone-gdrive: _ensure-collections
    {{ap}} playbooks/rclone-gdrive.yml

# Run only the Bitwarden playbook (optional password manager alternative,
# not part of `just setup`).
bitwarden: _ensure-collections
    {{ap}} playbooks/bitwarden.yml

# Run the Proton Pass playbook: desktop client (AUR) + CLI (official
# installer script). Optional password manager alternative, not part of
# `just setup`.
proton-pass: _ensure-collections
    {{ap}} playbooks/proton-pass.yml

# Run only the Proton Pass CLI install (no root needed).
proton-pass-cli: _ensure-collections
    ansible-playbook playbooks/proton-pass.yml --tags proton-pass-cli

# Run only the Podman (rootless) play.
podman: _ensure-collections
    {{ap}} site.yml --tags podman

# Run the Distrobox play (the tag also runs the Podman play first).
distrobox: _ensure-collections
    {{ap}} site.yml --tags distrobox

# Install Flatpak and enable the Flathub remote.
flatpak: _ensure-collections
    {{ap}} site.yml --tags flatpak

# Install Homebrew for Linux and symlink brew into /usr/local/bin.
# Not part of `just setup` — run explicitly (`playbooks/homebrew.yml` is
# not imported by site.yml).
homebrew: _ensure-collections
    {{ap}} playbooks/homebrew.yml

# Install snapd (AUR) and enable it (just the snapd play).
snapd: _ensure-collections
    {{ap}} site.yml --tags snapd

# Install Visual Studio Code from the official snap (the tag also runs the
# snapd play first).
vscode: _ensure-collections
    {{ap}} site.yml --tags vscode

# Build the libfprint (goodix538d) fork as a package and install it in place
# of the official libfprint. Uses makepkg on the host (no container).
libfprint: _ensure-collections
    {{ap}} site.yml --tags libfprint

# Bind SUPER+[ / SUPER+] to resize the focused column on the
# scrolling layout.
hypr-scrolling-resize: _ensure-collections
    ansible-playbook site.yml --tags hypr-scrolling-resize

# Set up the EPSON L4160 printer queue (CUPS driverless/IPP Everywhere).
printer: _ensure-collections
    {{ap}} site.yml --tags printer

# Set the monitor scale to 100% and compensate with larger shell/terminal
# and GTK UI font sizes.
text-size: _ensure-collections
    ansible-playbook site.yml --tags text-size

# Sync the night light to today's real sunrise/sunset.
nightlight-solar: _ensure-collections
    {{ap}} site.yml --tags nightlight-solar

# Remap Caps Lock via keyd (tap=Esc, hold=Ctrl, Shift+CapsLock=CapsLock).
capslock: _ensure-collections
    {{ap}} site.yml --tags capslock

# Install Inkscape + svg2tikz (AUR), an extension exporting SVG paths as TikZ/PGF for LaTeX.
inkscape: _ensure-collections
    {{ap}} site.yml --tags inkscape

# Install the Omadwaita Omarchy themes (Adwaita-based: Omadwaita = dark TUI +
# light GTK, Omadwaita Light, Omadwaita Dark). Installs only; doesn't apply.
omadwaita-themes: _ensure-collections
    ansible-playbook site.yml --tags omadwaita-themes

# Hide the Limine boot menu (quiet: yes + timeout: 1)
# for a flicker-free boot; a 1-second key window still reveals the menu.
limine-silent-boot: _ensure-collections
    {{ap}} site.yml --tags limine-silent-boot

# Install ble.sh (AUR blesh-git) and load it by default in Bash, with
# autosuggestions + syntax highlighting.
blesh: _ensure-collections
    {{ap}} site.yml --tags blesh

# Make the starship prompt work inside distrobox containers and show the
# container's name (Omarchy's bash rc from /run/host + starship env_var).
starship-distrobox: _ensure-collections
    ansible-playbook site.yml --tags starship-distrobox

# Activate AppArmor in the kernel (lsm= via a limine-entry-tool drop-in) without
# loading the distro profiles. Needs a reboot. Not part of `just setup`.
apparmor: _ensure-collections
    {{ap}} playbooks/apparmor.yml

# Same as `just apparmor`, plus apparmor.service loading the distro profiles
# (unix-chkpwd, avahi-daemon, ...). Not part of `just setup`.
apparmor-profiles: _ensure-collections
    {{ap}} playbooks/apparmor.yml -e apparmor_load_profiles=true

# Remove the leftover libfprint build container from before libfprint was
# packaged with a PKGBUILD (keeps the installed driver).
libfprint-destroy-container:
    distrobox rm -f libfprint-build

# Build the BGRT-derived boot theme (Omarchy theme + Plymouth theme) and
# set it as the default boot splash. Not part of `setup` — rewrites the
# default Plymouth theme and rebuilds the initramfs.
bgrt-theme: _ensure-collections
    {{ap}} playbooks/bgrt-theme.yml

# Secure Boot (Limine + sbctl). Not part of `setup` — run explicitly,
# twice, with a firmware reboot in between (see the playbook header).
secureboot: _ensure-collections
    {{ap}} playbooks/secureboot.yml

# Import the Yubikey's public GPG key. Needs the Yubikey plugged in.
gpg-yubikey: _ensure-collections
    {{ap}} playbooks/yubikey.yml --tags gpg-yubikey

# Import the Yubikey's resident FIDO2 SSH keys and configure SSH to use
# one for GitHub (10-minute ControlMaster). Standalone script, not
# Ansible: the FIDO2 PIN prompt needs a real terminal. Needs the Yubikey
# plugged in.
ssh-yubikey:
    scripts/ssh-yubikey.sh import

# Undo the GitHub SSH drop-in — for migrating to an ssh-agent.
ssh-yubikey-disable:
    scripts/ssh-yubikey.sh disable
