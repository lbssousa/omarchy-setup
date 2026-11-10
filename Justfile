set shell := ["bash", "-uc"]

# Two phases (see system.yml and user.yml), both run through
# scripts/run-phase.sh: the system phase under `run0 --empower` (see
# run-empowered.sh: one polkit authentication up front, then every
# `become: true` task's run0 inside passes without prompting again), for
# administrators only; the user phase as plain ansible-playbook, for every
# user in their own session. Both apply the features and apps chosen with
# `just configure` (catalog: features.yml, docs/features.md).

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

# gum draws the `just configure` menu (it ships with Omarchy).
_ensure-gum:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v gum >/dev/null; then
        echo "gum not found; installing via pacman..."
        run0 pacman -S --needed --noconfirm gum
    fi

# Choose the features and apps to apply (a gum menu); saved to
# ~/.config/omarchy-setup/features.yml, offers to apply them right after.
configure: _ensure-gum _ensure-collections
    scripts/configure.sh

# Every automation for your own account: the system phase (needs an
# administrator; authenticate once, in the polkit dialog that appears at the
# start), then your user phase. Asks for your choices first if you never
# made any.
setup: _ensure-collections
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -f ${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-setup/features.yml ]]; then
        just configure
    else
        just system user
    fi

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

# Apply only the given features now (ids from features.yml, or `apps` for
# every app category), in both phases (the system half needs an
# administrator), even those switched off in your choices. E.g.
# `just apply capslock printer`, `just apply apps`.
apply +IDS: _ensure-collections
    #!/usr/bin/env bash
    set -euo pipefail
    ids="{{IDS}}"
    tags="always,${ids// /,}"
    export OMARCHY_SETUP_ENABLE="$ids"
    if id -nG | tr ' ' '\n' | grep -qx wheel; then
        scripts/run-phase.sh system system.yml --tags "$tags"
    else
        echo "Skipping the system half (administrators only)."
    fi
    scripts/run-phase.sh user user.yml --tags "$tags"

# Update the accounts in omarchy_users (group_vars/all/users.yml) that exist on
# this machine, or create specific accounts: `just users` updates existing
# accounts without creating new ones automatically; `just users <name>...`
# creates or updates the named accounts from omarchy_users (or `--all` to
# create all). Then offers to set the password of each account that needs one: a
# new (still locked) account and, on an encrypted disk, one whose password
# doesn't open it yet. omarchy-mu-user-password asks for their password and
# yours. Each person's password is also their own disk key and picks them at the
# disk prompt and the login screen, so it has to be nobody else's; they can
# change it later from Setup › Users › Change Password.
users *NAMES: _ensure-collections
    #!/usr/bin/env bash
    set -euo pipefail
    extra_args=()
    if [[ "${1:-}" == "--all" ]]; then
        extra_args=(-e "users_create_all=true")
    elif [[ $# -gt 0 ]]; then
        json=$(printf '%s\n' "$@" | jq -R . | jq -s -c .)
        extra_args=(-e "users_filter=$json")
    fi
    scripts/run-phase.sh system system.yml --tags always,users "${extra_args[@]}"
    encrypted=false
    [[ $(lsblk -no TYPE "$(findmnt -no SOURCE / | sed 's/\[.*//')" 2>/dev/null | head -1) == crypt ]] && encrypted=true
    for u in $(getent group omarchy-users wheel | cut -d: -f4 | tr , "\n" | sort -u); do
        [[ -n $u ]] || continue
        if [[ $(sudo passwd -S "$u" | cut -d" " -f2) == L ]]; then
            echo "Account $u has no password yet."
        elif $encrypted && ! sudo awk -v u="$u" '$4 == u { found = 1 } END { exit !found }' /etc/omarchy-multiuser/slots 2>/dev/null; then
            echo "The password of $u doesn't open the disk yet."
        else
            continue
        fi
        read -rp "Set it now? [Y/n] " answer
        [[ $answer == [nN]* ]] && continue
        omarchy-mu-user-password "$u" || echo "Skipped: run omarchy-mu-user-password $u later."
    done

# Publish the committed HEAD to /opt/omarchy-setup and install
# omarchy-setup-user, which every user runs for their own phase.
publish: _ensure-collections
    scripts/run-phase.sh system system.yml --tags always,shared-checkout

# Syntax-check every entry point, the system/user phase boundary, the
# feature catalog against the plays' tags, and docs/features.md.
check: _ensure-collections
    #!/usr/bin/env bash
    set -euo pipefail
    ansible-playbook --syntax-check site.yml >/dev/null
    for p in playbooks/system/*.yml playbooks/user/*.yml playbooks/*/apps/*.yml; do
        ansible-playbook --syntax-check "$p" >/dev/null
    done
    echo "Syntax OK."
    scripts/check-phases.sh
    python3 scripts/features.py check
    if ! diff -q <(python3 scripts/features.py doc) docs/features.md >/dev/null; then
        echo "docs/features.md is out of date: run \`just docs\`." >&2
        exit 1
    fi
    echo "docs/features.md is up to date."

# Regenerate docs/features.md from features.yml.
docs:
    python3 scripts/features.py doc > docs/features.md

# List the UEFI boot entries left over from earlier installs (partition
# gone, loader missing, duplicates); changes nothing. Standalone script.
efi-cleanup:
    scripts/efi-boot-cleanup.sh

# Remove those entries (asks first; saves the current list to /root).
efi-cleanup-apply:
    run0 scripts/efi-boot-cleanup.sh --apply

# Install TeX Live, LilyPond and Gregorio directly on this machine (no
# containers, no Ansible) — see local-typesetting/README.md. A long
# network install; not part of `just setup`. Needs sudo.
typesetting:
    ./local-typesetting/install-typesetting.sh

# Record the versions of Omarchy's bash files that the fish port follows,
# after reviewing a change the fish play warned about.
fish-upstream-hash:
    cd /usr/share/omarchy/default/bash && sha256sum rc shell aliases functions init envs env-bootstrap completions inputrc fns/* > "{{justfile_directory()}}/playbooks/files/fish/UPSTREAM.sha256"

# Import the Yubikey's resident FIDO2 SSH keys and configure SSH to use
# one for GitHub (10-minute ControlMaster). Standalone script, not
# Ansible: the FIDO2 PIN prompt needs a real terminal. Needs the Yubikey
# plugged in.
ssh-yubikey:
    scripts/ssh-yubikey.sh import

# Undo the GitHub SSH drop-in — for migrating to an ssh-agent.
ssh-yubikey-disable:
    scripts/ssh-yubikey.sh disable
