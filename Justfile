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

# Run every automation.
setup: _ensure-collections
    ansible-playbook site.yml --ask-become-pass

# Run only the pt-BR localization playbook.
ptbr: _ensure-collections
    ansible-playbook site.yml --ask-become-pass --tags ptbr

# Run only the Bitwarden playbook.
bitwarden: _ensure-collections
    ansible-playbook site.yml --ask-become-pass --tags bitwarden

# Run only the Podman (rootless) playbook.
podman: _ensure-collections
    ansible-playbook site.yml --ask-become-pass --tags podman

# Run only the Distrobox playbook.
distrobox: _ensure-collections
    ansible-playbook site.yml --ask-become-pass --tags distrobox

# Build and install libfprint (goodix538d). Requires podman + distrobox.
libfprint: _ensure-collections
    ansible-playbook site.yml --ask-become-pass --tags libfprint

# Remove the libfprint build container (keeps the installed driver).
libfprint-destroy-container:
    distrobox rm -f libfprint-build
