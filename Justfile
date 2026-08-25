set shell := ["bash", "-uc"]

default:
    @just --list

# Install ansible via pacman if it isn't already on PATH.
_ensure-ansible:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v ansible-playbook >/dev/null; then
        echo "ansible-playbook não encontrado; instalando via pacman..."
        sudo pacman -S --needed --noconfirm ansible
    fi

# Install collections required by the playbooks (community.general).
_ensure-collections: _ensure-ansible
    ansible-galaxy collection install -r requirements.yml

# Run every automation. Privilege escalation is sudo (ansible.cfg
# default) with --ask-become-pass: type your password once at the
# start -- it's the fallback if the fingerprint reader doesn't
# cooperate (pam_fprintd is still tried first, silently, no on-screen
# prompt for it -- see ansible.cfg). sudo's own timestamp (~15 min)
# means only the first privileged task of the run normally prompts.
setup: _ensure-collections
    ansible-playbook site.yml --ask-become-pass

# Lower sudo's passwd_timeout (default 5 min) so a `become: true` fired
# from an unattended/hidden terminal gives up quickly instead of
# hanging (see playbooks/sudo.yml).
sudo: _ensure-collections
    ansible-playbook site.yml --tags sudo --ask-become-pass

# Raise polkitd's ExpirationSeconds -- helps other polkit-based desktop
# tools (pkexec and friends), not this repo's own become (see
# playbooks/polkit.yml).
polkit: _ensure-collections
    ansible-playbook site.yml --tags polkit --ask-become-pass

# Run only the NVIDIA playbook.
nvidia: _ensure-collections
    ansible-playbook site.yml --tags nvidia --ask-become-pass

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

# Hyprland: make SUPER+MINUS/SUPER+EQUAL also resize the current column
# on the scrolling layout. No privileged tasks -- no --ask-become-pass.
hypr-scrolling-resize: _ensure-collections
    ansible-playbook site.yml --tags hypr-scrolling-resize

# Remove the libfprint build container (keeps the installed driver).
libfprint-destroy-container:
    distrobox rm -f libfprint-build

# Secure Boot (Limine + sbctl). Deliberately NOT part of `setup` — run
# explicitly, twice, with a firmware reboot in between (see the
# playbook's own header for the full two-step flow).
secureboot: _ensure-collections
    ansible-playbook playbooks/secureboot.yml --ask-become-pass

# Import the Yubikey's public GPG key (gpg --card-edit fetch).
# Deliberately NOT part of `setup` -- needs the Yubikey plugged in.
gpg-yubikey: _ensure-collections
    ansible-playbook playbooks/yubikey-gpg.yml --ask-become-pass

# Download the Yubikey's resident (discoverable) FIDO2 SSH keys
# (ssh-keygen -K). Deliberately NOT part of `setup` -- needs the
# Yubikey plugged in, and a PIN/touch prompt on the real terminal.
ssh-yubikey: _ensure-collections
    ansible-playbook playbooks/yubikey-ssh.yml --ask-become-pass
