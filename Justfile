set shell := ["bash", "-uc"]

# Two phases (see system.yml and user.yml), both run through
# scripts/run-phase.sh: the system phase under `run0 --empower` (see
# run-empowered.sh: one polkit authentication up front, then every
# `become: true` task's run0 inside passes without prompting again), for
# administrators only; the user phase as plain ansible-playbook, for every
# user in their own session. Each loads users/$USER.yml.

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

# Every automation for your own account: the system phase (needs an
# administrator; authenticate once, in the polkit dialog that appears at the
# start), then your user phase.
setup: system user

# The system phase: packages, /etc, PAM, SDDM, signed plugin builds, user
# accounts. Administrators (wheel) only; rerun after adding a user.
system: _ensure-collections
    scripts/run-phase.sh system system.yml

# Your user phase: your ~/.config, session services and shell plugins, with
# your settings from users/$USER.yml. Run it as yourself, in your graphical
# session; other users run only this (`omarchy-setup-user` from any
# account, once an administrator has published the shared checkout).
user: _ensure-collections
    scripts/run-phase.sh user user.yml

# Create or update the accounts in omarchy_users (group_vars/all/users.yml),
# then set a password for each new (still locked) one and, for accounts with
# `luks: true`, offer a disk unlock password of their own. One polkit
# authentication for the whole recipe.
users: _ensure-collections
    #!/usr/bin/env bash
    set -euo pipefail
    scripts/run-phase.sh system system.yml --tags users
    luks=$(python3 -c 'import yaml; print(" ".join(u["name"] for u in yaml.safe_load(open("group_vars/all/users.yml"))["omarchy_users"] if u.get("luks")))')
    ./run-empowered.sh env LUKS_USERS="$luks" bash -c '
        for u in $(getent group omarchy-users wheel | cut -d: -f4 | tr , "\n" | sort -u); do
            [[ -n $u ]] || continue
            if [[ $(run0 passwd -S "$u" | cut -d" " -f2) == L ]]; then
                echo "New account $u: choose its password."
                until run0 passwd "$u"; do echo "Try again."; done
            fi
        done
        for u in $LUKS_USERS; do
            if ! run0 grep -qs "^$u " /etc/omarchy-multiuser/luks-slots; then
                read -rp "Add a disk unlock password for $u now? [y/N] " answer
                [[ $answer == [yYsS]* ]] && run0 omarchy-mu-luks-enroll "$u"
            fi
        done
        true'

# Publish the committed HEAD to /opt/omarchy-setup and install
# omarchy-setup-user, which every user runs for their own phase.
publish: _ensure-collections
    scripts/run-phase.sh system system.yml --tags shared-checkout

# Syntax-check every entry point and the system/user phase boundary.
check: _ensure-collections
    #!/usr/bin/env bash
    set -euo pipefail
    ansible-playbook --syntax-check site.yml >/dev/null
    for p in playbooks/system/*.yml playbooks/user/*.yml; do
        ansible-playbook --syntax-check "$p" >/dev/null
    done
    echo "Syntax OK."
    scripts/check-phases.sh

# A feature in both phases: its system half (when you're an administrator;
# otherwise it's skipped with a note), then yours.
_both TAG: _ensure-collections
    #!/usr/bin/env bash
    set -euo pipefail
    if id -nG | tr ' ' '\n' | grep -qx wheel; then
        scripts/run-phase.sh system system.yml --tags {{TAG}}
    else
        echo "Skipping the system half of {{TAG}} (administrators only)."
    fi
    scripts/run-phase.sh user user.yml --tags {{TAG}}

# Same, for the playbooks outside site.yml (playbooks/{system,user}/NAME.yml).
_both-playbook NAME: _ensure-collections
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -f playbooks/system/{{NAME}}.yml ]]; then
        if id -nG | tr ' ' '\n' | grep -qx wheel; then
            scripts/run-phase.sh system playbooks/system/{{NAME}}.yml
        else
            echo "Skipping the system half of {{NAME}} (administrators only)."
        fi
    fi
    if [[ -f playbooks/user/{{NAME}}.yml ]]; then
        scripts/run-phase.sh user playbooks/user/{{NAME}}.yml
    fi

# Build and install omarchy-multiuser from its signed release tag (the
# multi-user greeter, per-user FIDO2/fingerprint, migrations for non-admins)
# and switch SDDM to it, without autologin.
omarchy-multiuser: _ensure-collections
    scripts/run-phase.sh system system.yml --tags omarchy-multiuser

# Only the SDDM part: multi-user greeter, autologin removed.
sddm: _ensure-collections
    scripts/run-phase.sh system system.yml --tags sddm

# Raise polkitd's authentication cache window.
polkit: _ensure-collections
    scripts/run-phase.sh system system.yml --tags polkit

# Pin the sudo/polkit PAM order: fingerprint, then FIDO2/U2F key, then
# password (rerun after omarchy-setup-security-fingerprint/-fido2).
pam-auth-order: _ensure-collections
    scripts/run-phase.sh system system.yml --tags pam-auth-order

# Install Flatpak, enable the Flathub remote, install Bazaar (the Flathub
# app-store frontend) and expose the Flatpak export dirs on XDG_DATA_DIRS.
flatpak: _ensure-collections
    @just _both flatpak

# Install Firefox from Flathub (org.mozilla.firefox), enable tab apps
# (Taskbar Tabs) by default, set the default page font size and install the
# firefox.desktop shim for Omarchy's browser helpers.
firefox: _ensure-collections
    @just _both firefox

# Create the Firefox Taskbar Tabs ("tab apps") in firefox_taskbar_apps
# (users/$USER.yml), remove Omarchy's launchers for the same sites and point
# the webapp keybinds at them. Firefox must be closed while this runs. No
# root needed.
firefox-taskbar-apps: _ensure-collections
    scripts/run-phase.sh user user.yml --tags firefox-taskbar-apps

# Set git user.name/user.email from users/$USER.yml.
git-identity: _ensure-collections
    scripts/run-phase.sh user user.yml --tags git-identity

# Make Firefox the default browser with omarchy-default-browser
# (unless it already is). No root needed.
default-browser: _ensure-collections
    scripts/run-phase.sh user user.yml --tags default-browser

# Install ONLYOFFICE Desktop Editors from Flathub (org.onlyoffice.desktopeditors)
# and remove the pre-installed native libreoffice-fresh.
onlyoffice: _ensure-collections
    scripts/run-phase.sh system system.yml --tags onlyoffice

# Replace Omarchy's pre-installed Kdenlive, OBS Studio, Pinta and Xournal++
# with their Flathub builds.
flathub-apps: _ensure-collections
    scripts/run-phase.sh system system.yml --tags flathub-apps

# Install Emacs + AUCTeX, yasnippet (GNU ELPA) and lsp-mode (MELPA) with the classic beige-on-teal theme.
emacs: _ensure-collections
    @just _both emacs

# Install Zed (Omarchy theme integration), set every font size to 25px
# and the buffer font to JetBrainsMono Nerd Font.
zed: _ensure-collections
    @just _both zed

# Install Rust (if needed) and build/install gregorio-lsp, grelint and
# grefmt from source.
gregorio-lsp: _ensure-collections
    @just _both gregorio-lsp

# Make Zathura (Flathub org.pwmt.zathura) the default PDF viewer; Papers
# stays native as an optional viewer (sushi depends on it); Evince is removed.
pdf-viewer: _ensure-collections
    @just _both pdf-viewer

# Install the Flea file manager and make it the default (folders, keybinds, file dialogs).
file-manager: _ensure-collections
    @just _both file-manager

# Build/install omapin (GnuPG prompts in the polkit-style shell
# dialog) and make gpg-agent use it. Run from inside the graphical session.
# Needs the Yubikey's GPG key in the keyring (`just gpg-yubikey` first).
pinentry: _ensure-collections
    @just _both pinentry

# Build/install ssh-askpass-omarchy (SSH prompts in the polkit-style shell
# dialog) and configure SSH to use it. Run from inside the graphical session.
# Needs the Yubikey's GPG key in the keyring (`just gpg-yubikey` first).
ssh-askpass: _ensure-collections
    @just _both ssh-askpass

# Rebuild Arch's openssh with the patch that sends security key touch
# requests to SSH_ASKPASS when ssh runs in a terminal. Re-run after each
# openssh update from the repos.
openssh-askpass: _ensure-collections
    scripts/run-phase.sh system system.yml --tags openssh-askpass

# Replace Omarchy's polkit agent with polkit-omarchy (touch prompt for
# pam_u2f security keys). Run from inside the graphical session.
# Needs the Yubikey's GPG key in the keyring (`just gpg-yubikey` first).
polkit-agent: _ensure-collections
    @just _both polkit-agent

# Install the list of third-party shell plugins in omarchy_plugins
# (group_vars/all/main.yml) — Radio Atlas first — cloned by
# `omarchy plugin add`, pinned to each entry's ref, and placed in the bar
# section the entry asks for. Run from inside the graphical session; root is
# only needed if one of the plugins' runtime dependencies is missing.
plugins: _ensure-collections
    @just _both plugins

# Make the open/save file dialogs of non-GNOME apps Flea's picker (installs Flea first).
file-chooser: _ensure-collections
    @just _both file-chooser

# Enable LazyVim's LaTeX extra and install gregorio.nvim (GABC/NABC).
lazyvim: _ensure-collections
    scripts/run-phase.sh user user.yml --tags lazyvim

# Install TeX Live, LilyPond and Gregorio directly on this machine (no
# containers, no Ansible) — see local-typesetting/README.md. A long
# network install; not part of `just setup`. Needs sudo.
typesetting:
    ./local-typesetting/install-typesetting.sh

# Run only the pt-BR localization playbook.
ptbr: _ensure-collections
    @just _both ptbr

# Install Bitwarden from Flathub (com.bitwarden.desktop), the password
# manager, and its biometric unlock polkit action; in the user phase, deploy
# its autostart entry, wire its SSH agent to SSH_AUTH_SOCK and rebind
# SUPER+SHIFT+SLASH to Bitwarden. Removes KeePassXC, the previous default.
bitwarden: _ensure-collections
    @just _both bitwarden

# Create the rclone config + systemd --user mounts for Google Drive. Needs
# RCLONE_GDRIVE_CLIENT_ID and RCLONE_GDRIVE_CLIENT_SECRET in the environment on
# the first run (reused from rclone.conf afterwards). Not part of `just setup`;
# only the package install needs root.
rclone-gdrive: _ensure-collections
    @just _both-playbook rclone-gdrive

# Run the Proton Pass playbook: desktop client (AUR proton-pass-bin) + CLI
# (Homebrew). Optional password manager alternative to Bitwarden, not part
# of `just setup`; takes over SUPER+SHIFT+SLASH.
proton-pass: _ensure-collections
    @just _both-playbook proton-pass

# Run only the Proton Pass CLI install (no root needed).
proton-pass-cli: _ensure-collections
    scripts/run-phase.sh user playbooks/user/proton-pass.yml --tags proton-pass-cli

# Run only the Podman (rootless) play.
podman: _ensure-collections
    @just _both podman

# Run the Distrobox play (the tag also runs the Podman play first).
distrobox: _ensure-collections
    @just _both distrobox

# Install Nix (Arch package, multi-user daemon) with the store on its own
# btrfs subvolume, flakes enabled, and its profiles on the session PATH.
# Also runs the direnv and nix-direnv plays.
nix: _ensure-collections
    @just _both nix

# Install direnv and hook it into bash (~/.bashrc) and fish (vendor_conf.d).
direnv: _ensure-collections
    @just _both direnv

# Install Homebrew for Linux and a brew launcher in /usr/local/bin.
# Not part of `just setup` — run explicitly (`playbooks/system/homebrew.yml` is
# not imported by site.yml).
homebrew: _ensure-collections
    @just _both-playbook homebrew

# Build the libfprint (goodix538d) fork as a package and install it in place
# of the official libfprint. Uses makepkg on the host (no container).
libfprint: _ensure-collections
    scripts/run-phase.sh system system.yml --tags libfprint

# Bind SUPER+[ / SUPER+] to resize the focused column on the
# scrolling layout.
hypr-scrolling-resize: _ensure-collections
    scripts/run-phase.sh user user.yml --tags hypr-scrolling-resize

# Set up the EPSON L4160 printer queue (CUPS driverless/IPP Everywhere).
printer: _ensure-collections
    @just _both printer

# Set the monitor scale to 100% and compensate with larger shell/terminal
# and GNOME default GTK UI font sizes.
text-size: _ensure-collections
    scripts/run-phase.sh user user.yml --tags text-size

# Sync the night light to today's real sunrise/sunset.
nightlight-solar: _ensure-collections
    @just _both nightlight-solar

# Remap Caps Lock via keyd (tap=Esc, hold=Ctrl, Shift+CapsLock=CapsLock).
capslock: _ensure-collections
    @just _both capslock

# Install Inkscape + svg2tikz (AUR), an extension exporting SVG paths as TikZ/PGF for LaTeX.
inkscape: _ensure-collections
    scripts/run-phase.sh system system.yml --tags inkscape

# Install the Omadwaita Omarchy themes (Adwaita-based: Omadwaita = dark TUI +
# light GTK, Omadwaita Light, Omadwaita Dark). Installs only; doesn't apply.
omadwaita-themes: _ensure-collections
    scripts/run-phase.sh user user.yml --tags omadwaita-themes

# Install the Omaraptor Omarchy themes (GNOME palette + Bluefin wallpapers:
# Omaraptor = dark TUI + light GTK, Omaraptor Light, Omaraptor Dark). Installs only; doesn't apply.
omaraptor-themes: _ensure-collections
    scripts/run-phase.sh user user.yml --tags omaraptor-themes

# Switch the Omaraptor theme to its night variant (Omaraptor Dark) after sunset
# and back after sunrise, with a systemd --user timer.
omaraptor-theme-auto: _ensure-collections
    scripts/run-phase.sh user user.yml --tags omaraptor-theme-auto

# Hide the Limine boot menu (quiet: yes + timeout: 1)
# for a flicker-free boot; a 1-second key window still reveals the menu.
limine-silent-boot: _ensure-collections
    scripts/run-phase.sh system system.yml --tags limine-silent-boot

# Install ble.sh (AUR blesh-git) and load it by default in Bash, with
# autosuggestions + syntax highlighting.
blesh: _ensure-collections
    @just _both blesh

# Install Fish shell and make it the default login shell, reusing
# Omarchy's Starship prompt (~/.config/starship.toml).
fish: _ensure-collections
    @just _both fish

# Record the versions of Omarchy's bash files that the fish port follows,
# after reviewing a change the fish play warned about.
fish-upstream-hash:
    cd /usr/share/omarchy/default/bash && sha256sum rc shell aliases functions init envs env-bootstrap completions inputrc fns/* > "{{justfile_directory()}}/playbooks/files/fish/UPSTREAM.sha256"

# Make the starship prompt work inside distrobox containers and show the
# container's name (Omarchy's bash rc from /run/host + starship env_var).
starship-distrobox: _ensure-collections
    scripts/run-phase.sh user user.yml --tags starship-distrobox

# Starship prompt extras: a "❄ dev" badge inside Nix dev shells and ⇡N/⇣N
# for commits not pushed to/pulled from the upstream.
starship: _ensure-collections
    scripts/run-phase.sh user user.yml --tags starship

# Build the BGRT-derived boot theme (Omarchy theme + Plymouth theme) and
# set it as the default boot splash. Not part of `setup` — rewrites the
# default Plymouth theme and rebuilds the initramfs.
bgrt-theme: _ensure-collections
    @just _both-playbook bgrt-theme

# Secure Boot (Limine + sbctl). Not part of `setup` — run explicitly,
# twice, with a firmware reboot in between (see the playbook header).
secureboot: _ensure-collections
    scripts/run-phase.sh system playbooks/system/secureboot.yml

# Automatic LUKS unlock via TPM2 (systemd-cryptenroll). Not part of `setup` —
# run explicitly. Configures initramfs (sd-encrypt), crypttab and enrolls the
# TPM2 chip (PCRs 0+2+7) to automatically unlock the encrypted disk at boot.
tpm2: _ensure-collections
    scripts/run-phase.sh system playbooks/system/tpm2.yml

# Re-enroll TPM2: wipes existing TPM2 keyslot before enrolling (use after
# UEFI/BIOS firmware updates or Secure Boot key changes).
tpm2-wipe: _ensure-collections
    scripts/run-phase.sh system playbooks/system/tpm2.yml -e tpm2_wipe=true

# Interactive CLI TPM2 enrollment script (standalone, prompts directly in terminal).
tpm2-enroll:
    ./scripts/enroll-tpm2.sh

# Import the Yubikey's public GPG key. Needs the Yubikey plugged in.
gpg-yubikey: _ensure-collections
    @just _both-playbook yubikey

# Import the Yubikey's resident FIDO2 SSH keys and configure SSH to use
# one for GitHub (10-minute ControlMaster). Standalone script, not
# Ansible: the FIDO2 PIN prompt needs a real terminal. Needs the Yubikey
# plugged in.
ssh-yubikey:
    scripts/ssh-yubikey.sh import

# Undo the GitHub SSH drop-in — for migrating to an ssh-agent.
ssh-yubikey-disable:
    scripts/ssh-yubikey.sh disable
