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
#   disable  remove the GitHub SSH drop-in — do this when migrating to an
#            ssh-agent (Bitwarden, Proton Pass, ...) that serves the key
#   status   show the keys and whether the drop-in is active
#
# The SSH configuration lives in a single drop-in file,
# ~/.ssh/config.d/10-yubikey-github.conf, pulled in by one `Include` line
# this script puts at the top of ~/.ssh/config. `disable` deletes the
# drop-in; the Include line is harmless without it.
#
# Environment overrides:
#   GITHUB_KEY  private-key handle file name in ~/.ssh to use for GitHub
#               (default: id_ed25519_sk_rk_github.com_lbssousa — what
#               `ssh-keygen -K` names the key whose FIDO user is "lbssousa"
#               on application ssh:github.com)
set -euo pipefail

SSH_DIR="$HOME/.ssh"
DROPIN_DIR="$SSH_DIR/config.d"
DROPIN="$DROPIN_DIR/10-yubikey-github.conf"
MAIN_CONFIG="$SSH_DIR/config"
CM_DIR="$SSH_DIR/cm"
INCLUDE_LINE="Include config.d/*.conf"
GITHUB_KEY="${GITHUB_KEY:-id_ed25519_sk_rk_github.com_lbssousa}"

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

    cat >"$DROPIN" <<CONF
# Managed by omarchy-setup's scripts/ssh-yubikey.sh — GitHub over the
# Yubikey's resident FIDO2 key, no ssh-agent involved.
#
# To migrate to an ssh-agent: run \`scripts/ssh-yubikey.sh disable\`
# (or just delete this file).

Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/$GITHUB_KEY
    IdentitiesOnly yes
    AddKeysToAgent no

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
    if [[ -f $DROPIN ]]; then
        rm -f "$DROPIN"
        say "Removed $DROPIN — GitHub no longer uses the Yubikey drop-in"
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
