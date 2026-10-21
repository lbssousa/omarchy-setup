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

# Raise polkitd's authentication cache window.
polkit: _ensure-collections
    {{ap}} site.yml --tags polkit

# Pin the sudo/polkit PAM order: fingerprint, then FIDO2/U2F key, then
# password (rerun after omarchy-setup-security-fingerprint/-fido2).
pam-auth-order: _ensure-collections
    {{ap}} site.yml --tags pam-auth-order

# Install Brave Origin with Omarchy's browser installer
# (omarchy-install-browser brave-origin) plus Omarchy's web app container
# wiring (see brave-webapp-containers below).
brave: _ensure-collections
    {{ap}} site.yml --tags brave

# Convert Omarchy's preinstalled web apps (brave_pwa_webapps in
# group_vars/all/main.yml) into Brave Origin PWAs, each opening in its own
# Brave container, and drop leftover Firefox Taskbar Tab shortcuts. Needs
# root (writes /etc/brave/policies/managed). Every container named in
# brave_pwa_webapps must already exist in Brave.
brave-pwa-webapps: _ensure-collections
    {{ap}} playbooks/brave-pwa-webapps.yml

# Rerun just the Omarchy web app -> Brave container wiring (also installs
# the systemd --user watcher that reruns it when the launchers change).
# Launchers listed in brave_omarchy_webapp_containers get a trailing
# --container=<name> on their Exec=, so they open inside that Brave
# container. No root needed.
brave-webapp-containers: _ensure-collections
    ansible-playbook site.yml --tags brave-webapp-containers

# Make Brave Origin the default browser with omarchy-default-browser
# (unless it already is). No root needed.
default-browser: _ensure-collections
    ansible-playbook site.yml --tags default-browser

# Install ONLYOFFICE Desktop Editors (AUR onlyoffice-bin) and remove the
# pre-installed native libreoffice-fresh.
onlyoffice: _ensure-collections
    {{ap}} site.yml --tags onlyoffice

# Install Emacs + AUCTeX, yasnippet (GNU ELPA) and lsp-mode (MELPA) with the classic beige-on-teal theme.
emacs: _ensure-collections
    {{ap}} site.yml --tags emacs

# Install Zed (Omarchy theme integration), set every font size to 25px
# and the buffer font to JetBrainsMono Nerd Font.
zed: _ensure-collections
    {{ap}} site.yml --tags zed

# Install Rust (if needed) and build/install gregorio-lsp, grelint and
# grefmt from source.
gregorio-lsp: _ensure-collections
    ansible-playbook site.yml --tags gregorio-lsp

# Make Zathura (zathura + zathura-pdf-mupdf) the default PDF viewer +
# Papers (optional viewer); Evince stays installed (sushi depends on it).
pdf-viewer: _ensure-collections
    {{ap}} site.yml --tags pdf-viewer

# Install the Flea file manager and make it the default (folders, keybinds, file dialogs).
file-manager: _ensure-collections
    {{ap}} site.yml --tags file-manager

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

# Make the open/save file dialogs of non-GNOME apps Flea's picker (installs Flea first).
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

# Install KeePassXC (omarchy-pkg-add keepassxc), the password manager: autostart,
# SUPER+SHIFT+SLASH, browser manifests and the YubiKey auto-lock rule. The SSH agent stays off; add
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

# Run the Proton Pass playbook: desktop client (AUR proton-pass-bin) + CLI
# (Homebrew). Optional password manager alternative to KeePassXC, not part
# of `just setup`; takes over SUPER+SHIFT+SLASH.
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

# Install Nix (Arch package, multi-user daemon) with the store on its own
# btrfs subvolume, flakes enabled, and its profiles on the session PATH.
# Also runs the direnv and nix-direnv plays.
nix: _ensure-collections
    {{ap}} site.yml --tags nix

# Install direnv and hook it into bash (~/.bashrc) and fish (vendor_conf.d).
direnv: _ensure-collections
    {{ap}} site.yml --tags direnv

# Install Homebrew for Linux and a brew launcher in /usr/local/bin.
# Not part of `just setup` — run explicitly (`playbooks/homebrew.yml` is
# not imported by site.yml).
homebrew: _ensure-collections
    {{ap}} playbooks/homebrew.yml

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
# and GNOME default GTK UI font sizes.
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

# Install the Omaraptor Omarchy themes (GNOME palette + Bluefin wallpapers:
# Omaraptor = dark TUI + light GTK, Omaraptor Light, Omaraptor Dark). Installs only; doesn't apply.
omaraptor-themes: _ensure-collections
    ansible-playbook site.yml --tags omaraptor-themes

# Switch the Omaraptor theme to its night variant (Omaraptor Dark) after sunset
# and back after sunrise, with a systemd --user timer.
omaraptor-theme-auto: _ensure-collections
    ansible-playbook site.yml --tags omaraptor-theme-auto

# Hide the Limine boot menu (quiet: yes + timeout: 1)
# for a flicker-free boot; a 1-second key window still reveals the menu.
limine-silent-boot: _ensure-collections
    {{ap}} site.yml --tags limine-silent-boot

# Install ble.sh (AUR blesh-git) and load it by default in Bash, with
# autosuggestions + syntax highlighting.
blesh: _ensure-collections
    {{ap}} site.yml --tags blesh

# Install Fish shell and make it the default login shell, reusing
# Omarchy's Starship prompt (~/.config/starship.toml).
fish: _ensure-collections
    {{ap}} site.yml --tags fish

# Record the versions of Omarchy's bash files that the fish port follows,
# after reviewing a change the fish play warned about.
fish-upstream-hash:
    cd /usr/share/omarchy/default/bash && sha256sum rc shell aliases functions init envs env-bootstrap completions inputrc fns/* > "{{justfile_directory()}}/playbooks/files/fish/UPSTREAM.sha256"

# Make the starship prompt work inside distrobox containers and show the
# container's name (Omarchy's bash rc from /run/host + starship env_var).
starship-distrobox: _ensure-collections
    ansible-playbook site.yml --tags starship-distrobox

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
