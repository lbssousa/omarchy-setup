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

# Install Firefox and enable tab apps (Taskbar Tabs).
firefox: _ensure-collections
    {{ap}} site.yml --tags firefox

# Swap Omarchy's preinstalled web apps (taskbar_tab_webapp_swaps in
# group_vars/all/main.yml) for matching Firefox Taskbar Tabs, keeping
# each one's Hyprland keybind, and/or create brand-new Taskbar Tabs
# (taskbar_tab_webapp_creates — Firefox must be closed first). No root
# needed. Not part of `just setup`.
taskbar-tab-webapps: _ensure-collections
    ansible-playbook playbooks/taskbar-tab-webapps.yml

# Install Zed (Omarchy theme integration), set every font size to 25px
# and the buffer font to JetBrainsMono Nerd Font.
zed: _ensure-collections
    {{ap}} site.yml --tags zed

# Install Rust (if needed) and build/install gregorio-lsp, grelint and
# grefmt from source.
gregorio-lsp: _ensure-collections
    ansible-playbook site.yml --tags gregorio-lsp

# Make Zathura the default PDF viewer + Papers (optional viewer); Evince stays installed (sushi depends on it).
pdf-viewer: _ensure-collections
    {{ap}} site.yml --tags pdf-viewer

# Build/install pinentry-omarchy (GnuPG prompts in the polkit-style shell
# dialog) and make gpg-agent use it. Run from inside the graphical session.
pinentry: _ensure-collections
    {{ap}} site.yml --tags pinentry

# Make the open/save file dialogs of non-GNOME apps the GTK4 ones (xdg-desktop-portal-gnome).
file-chooser: _ensure-collections
    {{ap}} site.yml --tags file-chooser

# Enable LazyVim's LaTeX extra and install gregorio.nvim (GABC/NABC).
lazyvim: _ensure-collections
    ansible-playbook site.yml --tags lazyvim

# Install TeX Live (AUR texlive-installer, scheme-minimal + AISCGre-BR
# packages). Not part of `just setup` — run explicitly.
texlive: _ensure-collections
    {{ap}} playbooks/tex.yml --tags texlive

# Build and install Gregorio (lbssousa/gregorio) from source. Depends on
# TeX Live — the tag also runs the TeX Live play first. Not part of `just setup`.
gregorio: _ensure-collections
    {{ap}} playbooks/tex.yml --tags gregorio

# Run only the pt-BR localization playbook.
ptbr: _ensure-collections
    {{ap}} site.yml --tags ptbr

# Run only the OpenSSH agent (user session) play. Part of
# playbooks/keepassxc.yml (optional, not part of `just setup`).
ssh-agent: _ensure-collections
    ansible-playbook playbooks/keepassxc.yml --tags ssh-agent

# Run the KeePassXC playbook (OpenSSH agent play first, then KeePassXC).
# Optional password manager alternative, not part of `just setup`.
keepassxc: _ensure-collections
    {{ap}} playbooks/keepassxc.yml

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
homebrew: _ensure-collections
    {{ap}} site.yml --tags homebrew

# Install snapd (AUR) and enable it (just the snapd play).
snapd: _ensure-collections
    {{ap}} site.yml --tags snapd

# Install Visual Studio Code from the official snap (the tag also runs the
# snapd play first).
vscode: _ensure-collections
    {{ap}} site.yml --tags vscode

# Build and install libfprint (goodix538d). Requires podman + distrobox.
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

# Remove the libfprint build container (keeps the installed driver).
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

# Prepare for downloading the Yubikey's resident FIDO2 SSH keys. Needs
# the Yubikey plugged in.
ssh-yubikey: _ensure-collections
    {{ap}} playbooks/yubikey.yml --tags ssh-yubikey
