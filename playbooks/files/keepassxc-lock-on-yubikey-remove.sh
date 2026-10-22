#!/usr/bin/bash
# Locks every open KeePassXC database, in every user's session. Invoked by
# the udev rule in playbooks/system/keepassxc.yml when the YubiKey is
# unplugged: whoever was using it, each logged-in user's KeePassXC locks
# (the key may have unlocked any of them).
#
# Ported from lbssousa/nix-config's
# modules/system/security/keepassxc-yubikey-lock.nix.
set -eu

keepassxc_dbus_name="org.keepassxc.KeePassXC.MainWindow"

lock_for_user() {
  local username=$1 uid runtime_dir has_owner
  uid="$(id -u "$username")" || return 0
  runtime_dir="/run/user/$uid"
  [ -S "$runtime_dir/bus" ] || return 0

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
    *) return 0 ;;
  esac

  runuser -u "$username" -- env \
    XDG_RUNTIME_DIR="$runtime_dir" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus" \
    gdbus call --session \
      --dest "$keepassxc_dbus_name" \
      --object-path /keepassxc \
      --method org.keepassxc.KeePassXC.MainWindow.lockAllDatabases \
      >/dev/null 2>&1 || true
}

# Every user with a running systemd user manager (that is, logged in).
for username in $(loginctl list-users --no-legend | awk '{ print $2 }' | sort -u); do
  lock_for_user "$username"
done
