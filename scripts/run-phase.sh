#!/usr/bin/env bash
# Runs a playbook in one of the two phases, with the caller's own settings.
#
#   system  needs root for its tasks: refused unless you're an administrator
#           (wheel), then run under run-empowered.sh (one polkit
#           authentication up front).
#   user    runs as you, never under run0: refused as root or from an
#           empowered process. Needs your graphical session for most plays.
#
# Both load users/$USER.yml (your settings, if the file exists) and then
# ~/.config/omarchy-setup/local.yml (machine-local overrides, if any) as
# extra vars.
#
# Usage: scripts/run-phase.sh system|user <playbook> [ansible-playbook args]
set -euo pipefail

phase=${1:-}
playbook=${2:-}
[[ $phase == system || $phase == user ]] && [[ -n $playbook ]] || {
    sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0"
    exit 2
}
shift 2

cd "$(dirname "$(readlink -f "$0")")/.."

extra=()
[[ -f users/$USER.yml ]] && extra+=(-e "@users/$USER.yml")
local_vars=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-setup/local.yml
[[ -f $local_vars ]] && extra+=(-e "@$local_vars")

case $phase in
    system)
        if ! id -nG | tr ' ' '\n' | grep -qx wheel; then
            echo "The system phase is for administrators (wheel). Ask one to run \`just system\`; your part is \`just user\`." >&2
            exit 1
        fi
        exec ./run-empowered.sh ansible-playbook "$playbook" "${extra[@]}" "$@"
        ;;
    user)
        if (( EUID == 0 )) || id -nG | tr ' ' '\n' | grep -qx empower; then
            echo "Run the user phase as yourself (plain \`just user\`), not as root or under run-empowered.sh." >&2
            exit 1
        fi
        exec ansible-playbook "$playbook" "${extra[@]}" "$@"
        ;;
esac
