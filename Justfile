set shell := ["bash", "-uc"]

default:
    @just --list

# Install ansible via pacman if it isn't already on PATH.
_ensure-ansible:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v ansible-playbook >/dev/null; then
        echo "ansible-playbook not found; installing via pacman..."
        sudo pacman -S --needed --noconfirm ansible
    fi

# Install collections required by the playbooks (community.general).
_ensure-collections: _ensure-ansible
    ansible-galaxy collection install -r requirements.yml

# Run every automation. Type your sudo password once at the start.
setup: _ensure-collections
    ansible-playbook site.yml --ask-become-pass

# Lower sudo's passwd_timeout so an unattended become doesn't hang.
sudo: _ensure-collections
    ansible-playbook site.yml --tags sudo --ask-become-pass

# Raise polkitd's authentication cache window.
polkit: _ensure-collections
    ansible-playbook site.yml --tags polkit --ask-become-pass

# Run only the NVIDIA playbook.
nvidia: _ensure-collections
    ansible-playbook site.yml --tags nvidia --ask-become-pass

# Install Firefox and enable tab apps (Taskbar Tabs).
firefox: _ensure-collections
    ansible-playbook site.yml --tags firefox --ask-become-pass

# Install Zed (Omarchy theme integration), set every font size to 20px
# and the buffer font to JetBrainsMono Nerd Font.
zed: _ensure-collections
    ansible-playbook site.yml --tags zed --ask-become-pass

# Run only the pt-BR localization playbook.
ptbr: _ensure-collections
    ansible-playbook site.yml --tags ptbr --ask-become-pass

# Run only the Bitwarden playbook.
bitwarden: _ensure-collections
    ansible-playbook site.yml --tags bitwarden --ask-become-pass

# Run only the Podman (rootless) playbook.
podman: _ensure-collections
    ansible-playbook site.yml --tags podman --ask-become-pass

# Run only the Distrobox playbook.
distrobox: _ensure-collections
    ansible-playbook site.yml --tags distrobox --ask-become-pass

# Build and install libfprint (goodix538d). Requires podman + distrobox.
libfprint: _ensure-collections
    ansible-playbook site.yml --tags libfprint --ask-become-pass

# Bind SUPER+[ / SUPER+SHIFT+[ to resize the focused column on the
# scrolling layout.
hypr-scrolling-resize: _ensure-collections
    ansible-playbook site.yml --tags hypr-scrolling-resize

# Set up the EPSON L4160 printer queue (CUPS driverless/IPP Everywhere).
printer: _ensure-collections
    ansible-playbook site.yml --tags printer --ask-become-pass

# Scale up shell bar + terminal text size without scaling GTK apps.
text-size: _ensure-collections
    ansible-playbook site.yml --tags text-size

# Sync the night light to today's real sunrise/sunset.
nightlight-solar: _ensure-collections
    ansible-playbook site.yml --tags nightlight-solar --ask-become-pass

# Remap Caps Lock via keyd (tap=Esc, hold=Ctrl, Shift+CapsLock=CapsLock).
capslock: _ensure-collections
    ansible-playbook site.yml --tags capslock --ask-become-pass

# Remove the libfprint build container (keeps the installed driver).
libfprint-destroy-container:
    distrobox rm -f libfprint-build

# Secure Boot (Limine + sbctl). Not part of `setup` — run explicitly,
# twice, with a firmware reboot in between (see the playbook header).
secureboot: _ensure-collections
    ansible-playbook playbooks/secureboot.yml --ask-become-pass

# Import the Yubikey's public GPG key. Needs the Yubikey plugged in.
gpg-yubikey: _ensure-collections
    ansible-playbook playbooks/yubikey-gpg.yml --ask-become-pass

# Prepare for downloading the Yubikey's resident FIDO2 SSH keys. Needs
# the Yubikey plugged in.
ssh-yubikey: _ensure-collections
    ansible-playbook playbooks/yubikey-ssh.yml --ask-become-pass
