#!/usr/bin/env bash
# Runs a command (normally ansible-playbook) under `run0 --empower`.
#
# The command keeps running as YOUR user, so $HOME, $USER, ~/.config and
# `systemctl --user` all behave as usual, but with every capability and the
# "empower" group, for which systemd's stock polkit rule
# (/usr/share/polkit-1/rules.d/empower.rules) allows every action. You
# authenticate once, through the desktop's polkit dialog (fingerprint or
# password); every `become: true` task's own `run0 --user=root` inside then
# passes without another prompt.
#
# Why not rely on `become_method = run0` alone: Omarchy's shell registers a
# graphical polkit agent, so each run0 call pops up a dialog, and polkit
# doesn't retain the authorization between separate run0 processes (checked
# here with `run0 --no-ask-password` right after an approved run). A
# playbook run has dozens of privileged tasks: dozens of dialogs.
#
# No polkit rule is installed and nothing persists: the privileges live only
# in this process tree, for as long as the command runs. Per run0(1), other
# unprivileged processes of your user have privileges over an empowered
# process, so avoid running this with untrusted software going on in your
# session.
#
# run0 starts from a clean environment, so every variable of the caller is
# passed through by name (--setenv=NAME, no value = the current one): PATH
# (mise shims, ~/.cargo/bin), XDG_RUNTIME_DIR/DBUS_SESSION_BUS_ADDRESS
# (`systemctl --user`), HYPRLAND_INSTANCE_SIGNATURE (`hyprctl`), OMARCHY_PATH...
#
# Usage: ./run-empowered.sh ansible-playbook site.yml --tags <tag>
#        ./run-empowered.sh --help
set -euo pipefail

if [[ $# -eq 0 || $1 == -h || $1 == --help ]]; then
    sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0"
    exit 0
fi

setenv=()
while IFS='=' read -r -d '' name _; do
    if [[ $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ && $name != _ ]]; then
        setenv+=("--setenv=$name")
    fi
done < <(env -0)

exec run0 --empower "${setenv[@]}" "$@"
