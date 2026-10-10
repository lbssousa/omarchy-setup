#!/usr/bin/env bash
# Imports the Yubikey's resident (discoverable) FIDO2 SSH keys into ~/.ssh
# and wires GitHub to one of them, with a 10-minute ControlMaster so the
# PIN/touch is asked once per burst of git operations, not once per
# connection.
#
# A standalone script rather than an Ansible playbook: `ssh-keygen -K`
# asks for the FIDO2 PIN (and wants a touch) on a real terminal, and
# Ansible can't relay that prompt — the task would hang forever.
#
# Usage: scripts/ssh-yubikey.sh [import|enable|disable|status]
#   import   (default) download the resident keys, then enable the config
#   enable   (re)write the GitHub SSH drop-in, without touching the token
#   disable  turn the GitHub SSH drop-in off by renaming it to
#            <name>.conf.disabled — do this when migrating to an
#            ssh-agent (Bitwarden, Proton Pass, ...) that serves the key
#   status   show the keys and whether the drop-in is active
#
# The SSH configuration lives in one self-contained drop-in per key,
# ~/.ssh/config.d/<host>_<user>.conf (dots as underscores, e.g.
# github_com_lbssousa.conf), pulled in by one `Include config.d/*.conf`
# line this script puts at the top of ~/.ssh/config. A file that doesn't
# end in ".conf" is ignored by that glob, so `disable` just renames it and
# `enable` renames it back; the Include line is harmless without any.
#
# Environment overrides:
#   GITHUB_KEY  private-key handle file name in ~/.ssh to use for GitHub
#               (default: id_ed25519_sk_rk_github.com_lbssousa — what
#               `ssh-keygen -K` names the key whose FIDO user is "lbssousa"
#               on application ssh:github.com)
set -euo pipefail

SSH_DIR="$HOME/.ssh"
DROPIN_DIR="$SSH_DIR/config.d"
MAIN_CONFIG="$SSH_DIR/config"
CM_DIR="$SSH_DIR/cm"
INCLUDE_LINE="Include config.d/*.conf"
GITHUB_KEY="${GITHUB_KEY:-id_ed25519_sk_rk_github.com_lbssousa}"

# <host>_<user>.conf, from the handle name `ssh-keygen -K` wrote:
# id_ed25519_sk_rk_github.com_lbssousa -> github_com_lbssousa.conf
# (a handle with no user part gives plain github_com.conf).
dropin_name() {
    local suffix="${GITHUB_KEY#*github.com}"
    printf 'github_com%s.conf' "${suffix:+_${suffix#_}}"
}
DROPIN="$DROPIN_DIR/$(dropin_name)"
DROPIN_OFF="$DROPIN.disabled"
# Earlier versions of this script wrote a single numbered file.
LEGACY_DROPIN="$DROPIN_DIR/10-yubikey-github.conf"

say() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

ensure_dirs() {
    install -d -m 0700 "$SSH_DIR" "$DROPIN_DIR" "$CM_DIR"
}

ensure_packages() {
    # openssh for ssh-keygen, libfido2 for the sk-* provider's hidapi/CTAP2.
    if ! pacman -Q openssh libfido2 >/dev/null 2>&1; then
        say "Installing openssh and libfido2"
        run0 pacman -S --needed --noconfirm openssh libfido2
    fi
}

import_keys() {
    ensure_packages
    ensure_dirs

    # ssh-keygen -K writes into the current directory and can prompt to
    # overwrite existing files, so download into a scratch directory and
    # move over only what's new. The private "key" file is only a handle
    # (useless without the token), hence the empty passphrase: it spares
    # one extra prompt per key.
    local tmp
    tmp="$(mktemp -d "$SSH_DIR/.import.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" EXIT

    say "Downloading resident keys — enter the FIDO2 PIN and touch the Yubikey when it blinks"
    (cd "$tmp" && ssh-keygen -K -N '')

    local f name new=0 same=0 conflict=0
    shopt -s nullglob
    for f in "$tmp"/id_*; do
        name="$(basename "$f")"
        if [[ ! -e "$SSH_DIR/$name" ]]; then
            mv "$f" "$SSH_DIR/$name"
            chmod 0600 "$SSH_DIR/$name"
            [[ $name == *.pub ]] && chmod 0644 "$SSH_DIR/$name"
            [[ $name == *.pub ]] || say "New key: $name"
            [[ $name == *.pub ]] || new=$((new + 1))
        elif cmp -s "$f" "$SSH_DIR/$name"; then
            [[ $name == *.pub ]] || same=$((same + 1))
        else
            warn "$name already exists with different content — kept the existing one"
            conflict=$((conflict + 1))
        fi
    done
    shopt -u nullglob

    say "Imported $new new key(s); $same already present; $conflict conflict(s)"

    enable_config
}

# A hand-written `Host github.com` in the main config would win over
# (or duplicate) the drop-in — ssh takes the first value it finds.
warn_about_manual_block() {
    if [[ -f $MAIN_CONFIG ]] && grep -qiE '^[[:space:]]*Host[[:space:]]+(.*[[:space:]])?github\.com([[:space:]]|$)' "$MAIN_CONFIG"; then
        warn "$MAIN_CONFIG has its own 'Host github.com' block; it overlaps with the drop-in."
        warn "Remove it so this script is the only source of that configuration."
    fi
}

enable_config() {
    ensure_dirs

    [[ -f $SSH_DIR/$GITHUB_KEY ]] || {
        say "Keys in $SSH_DIR:"
        ls -1 "$SSH_DIR" | grep -E '^id_.*_sk_rk' | grep -v '\.pub$' | sed 's/^/    /' || true
        die "$SSH_DIR/$GITHUB_KEY not found — pick one above and rerun with GITHUB_KEY=<file>"
    }

    # Include must come before any Host/Match block to apply globally.
    if [[ ! -f $MAIN_CONFIG ]]; then
        printf '%s\n' "$INCLUDE_LINE" >"$MAIN_CONFIG"
        chmod 0600 "$MAIN_CONFIG"
    elif ! grep -qxF "$INCLUDE_LINE" "$MAIN_CONFIG"; then
        local t
        t="$(mktemp "$SSH_DIR/.config.XXXXXX")"
        { printf '%s\n\n' "$INCLUDE_LINE"; cat "$MAIN_CONFIG"; } >"$t"
        chmod 0600 "$t"
        mv "$t" "$MAIN_CONFIG"
        say "Added '$INCLUDE_LINE' to the top of $MAIN_CONFIG"
    fi

    # Leftovers of the single-file layout, and a previously disabled copy
    # of this very file, would otherwise duplicate or shadow it.
    rm -f "$LEGACY_DROPIN" "$DROPIN_OFF"

    cat >"$DROPIN" <<CONF
# Managed by omarchy-setup's scripts/ssh-yubikey.sh — authentication on
# github.com with the Yubikey's resident FIDO2 key $GITHUB_KEY,
# without the ssh-agent.
# To disable: scripts/ssh-yubikey.sh disable (renames this file to
# $(basename "$DROPIN").disabled), or rename it by hand to anything
# that doesn't end in ".conf".

Host github.com
    HostName github.com
    User git
    IdentityAgent none
    IdentitiesOnly yes
    AddKeysToAgent no
    IdentityFile ~/.ssh/$GITHUB_KEY

    # Reuse one authenticated connection for 10 minutes: the Yubikey
    # asks for a touch once instead of on every git operation.
    ControlMaster auto
    ControlPersist 10m
    ControlPath ~/.ssh/cm/%C
CONF
    chmod 0600 "$DROPIN"
    say "Wrote $DROPIN (key: $GITHUB_KEY)"
    warn_about_manual_block
}

disable_config() {
    if [[ -f $LEGACY_DROPIN ]]; then
        mv -f "$LEGACY_DROPIN" "$LEGACY_DROPIN.disabled"
        say "Disabled $LEGACY_DROPIN"
    fi
    if [[ -f $DROPIN ]]; then
        mv -f "$DROPIN" "$DROPIN_OFF"
        say "Renamed $DROPIN to $(basename "$DROPIN_OFF") — GitHub no longer uses the Yubikey drop-in"
    else
        say "Already disabled ($DROPIN doesn't exist)"
    fi
    # Close a ControlMaster still alive from the old configuration.
    if [[ -d $CM_DIR ]]; then
        ssh -O exit -o ControlPath="$CM_DIR/%C" github.com >/dev/null 2>&1 || true
    fi
}

show_status() {
    say "Resident key handles in $SSH_DIR:"
    find "$SSH_DIR" -maxdepth 1 -name 'id_*_sk_rk*' ! -name '*.pub' -printf '    %f\n' | sort
    if [[ -f $DROPIN ]]; then
        say "GitHub drop-in: ENABLED ($DROPIN)"
        grep -E '^\s*IdentityFile' "$DROPIN" | sed 's/^\s*/    /'
    elif [[ -f $LEGACY_DROPIN ]]; then
        say "GitHub drop-in: ENABLED, old single-file layout ($LEGACY_DROPIN) — rerun 'enable' to migrate"
    else
        say "GitHub drop-in: disabled"
    fi
    warn_about_manual_block
}

case "${1:-import}" in
    import)  import_keys ;;
    enable)  enable_config ;;
    disable) disable_config ;;
    status)  show_status ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' ;;
    *) die "unknown command '$1' (import|enable|disable|status)" ;;
esac
