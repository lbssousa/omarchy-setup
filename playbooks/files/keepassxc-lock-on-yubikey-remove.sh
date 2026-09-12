#!/usr/bin/bash
# Locks every open KeePassXC database for one user. Invoked by the udev
# rule in playbooks/keepassxc.yml when the YubiKey is unplugged.
#
# Ported from lbssousa/nix-config's
# modules/system/security/keepassxc-yubikey-lock.nix.
set -eu

username="$1"
uid="$(id -u "$username")"
runtime_dir="/run/user/$uid"
keepassxc_dbus_name="org.keepassxc.KeePassXC.MainWindow"

if [ ! -S "$runtime_dir/bus" ]; then
  exit 0
fi

has_owner="$(
  runuser -u "$username" -- env \
    XDG_RUNTIME_DIR="$runtime_dir" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus" \
    gdbus call --session \
      --dest org.freedesktop.DBus \
      --object-path /org/freedesktop/DBus \
      --method org.freedesktop.DBus.NameHasOwner \
      "$keepassxc_dbus_name" \
      2>/dev/null || true
)"

case "$has_owner" in
  *"(true,"*) ;;
  *)
    exit 0
    ;;
esac

runuser -u "$username" -- env \
  XDG_RUNTIME_DIR="$runtime_dir" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus" \
  gdbus call --session \
    --dest "$keepassxc_dbus_name" \
    --object-path /keepassxc \
    --method org.keepassxc.KeePassXC.MainWindow.lockAllDatabases \
    >/dev/null 2>&1 || true
