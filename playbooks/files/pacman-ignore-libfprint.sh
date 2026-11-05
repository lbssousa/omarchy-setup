#!/bin/bash
# Managed by playbooks/system/libfprint.yml.
#
# Keeps the goodix538d libfprint-git through a channel switch or
# `omarchy-refresh-pacman`: their `pacman -Syyuu` would swap it for the omarchy
# repo's build, whatever its epoch, and that build has no driver for the reader.
# They rewrite /etc/pacman.conf from a template first, so the line has to be
# added back every time, after the rewrite and before the transaction.
#
# Omarchy drops its sudo cache before this hook, so sudo asks again. If that's
# refused the switch still goes on, and the fork is lost until
# `just apply libfprint` restores it.
set -uo pipefail

CONF=/etc/pacman.conf
LINE="IgnorePkg = libfprint-git"

grep -qxF "$LINE" "$CONF" && exit 0

if ! sudo sed -i "/^\[options\]/a $LINE" "$CONF"; then
  echo "Could not pin libfprint-git: this update will downgrade it. Run \`just apply libfprint\` afterwards." >&2
  exit 1
fi
