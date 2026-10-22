#!/usr/bin/env bash
# Checks the boundary between the two phases (see system.yml / user.yml):
#
#   playbooks/user/    never becomes root, installs no packages (pacman, or
#                      Omarchy's omarchy-pkg-*/omarchy-install-* helpers,
#                      which sudo inside), so a user outside wheel can run it
#   playbooks/system/  never talks to a user session (systemctl --user,
#                      the Omarchy shell, Hyprland), which an administrator's
#                      run can only reach for their own account
#
# Comments are ignored. omarchy-install-chromium-* and
# omarchy-install-video-decode only touch the caller's home, so they're
# allowed in the user phase.
#
# Usage: scripts/check-phases.sh
set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."

status=0
report() {
    local rule=$1
    shift
    if [[ -n $* ]]; then
        echo "$rule:"
        printf '  %s\n' "$@"
        status=1
    fi
}

code() {
    # file:line:text for non-comment lines matching $1 in $2...
    local pattern=$1
    shift
    grep -nHE "$pattern" "$@" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'
}

mapfile -t hits < <(code 'become: *(true|yes)' playbooks/user/*.yml)
report "playbooks/user/ must not become root" "${hits[@]}"

mapfile -t hits < <(code 'community\.general\.pacman|omarchy-pkg-|omarchy-install-' playbooks/user/*.yml |
    grep -vE 'omarchy-install-(chromium-[a-z-]+|video-decode)')
report "playbooks/user/ must not install packages" "${hits[@]}"

mapfile -t hits < <(code 'systemctl +--user|scope: *user|omarchy-shell|omarchy-restart-shell|hyprctl' playbooks/system/*.yml)
report "playbooks/system/ must not talk to a user session" "${hits[@]}"

if (( status == 0 )); then
    echo "Phase boundaries OK."
fi
exit "$status"
