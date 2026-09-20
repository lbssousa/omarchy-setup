#!/bin/bash

# Omarchy `theme-set` hook, installed as
# ~/.config/omarchy/hooks/theme-set.d/omadwaita-light-apps. It is called
# with the snake-cased name of the theme that was just set.
#
# The "Omadwaita" theme has a dark TUI palette (colors.toml: mode = "dark")
# but light GUI apps. Omarchy derives GTK's scheme from that dark palette,
# so by the time this hook runs it has already set GTK to Adwaita-dark +
# prefer-dark (omarchy-theme-set-gnome). Put it back to light. Every other
# theme is left alone: setting one of them re-runs Omarchy's own step,
# restoring GTK to that theme's own values.
#
# The Chromium-family browsers need nothing here: their tint comes from the
# theme's chromium.theme, which the theme ships with a light seed (see
# playbooks/omadwaita-themes.yml), so Omarchy's own browser step already
# writes the light policy.

[[ $1 == omadwaita ]] || exit 0

# gsettings needs a user DBus session (absent e.g. during ISO installs).
if [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
  gsettings set org.gnome.desktop.interface color-scheme "prefer-light"
  gsettings set org.gnome.desktop.interface gtk-theme "Adwaita"
fi
