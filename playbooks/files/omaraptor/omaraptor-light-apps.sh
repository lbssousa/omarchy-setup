#!/bin/bash

# Omarchy `theme-set` hook, installed as
# ~/.config/omarchy/hooks/theme-set.d/omaraptor-light-apps. It is called
# with the snake-cased name of the theme that was just set.
#
# The "Omaraptor" theme has a dark TUI palette (colors.toml: mode = "dark")
# but light GUI apps. Omarchy derives GTK's scheme from that dark palette,
# so by the time this hook runs it has already set GTK to Adwaita-dark +
# prefer-dark (omarchy-theme-set-gnome). Put it back to light. Every other
# theme is left alone: setting one of them re-runs Omarchy's own step,
# restoring GTK to that theme's own values.
#
# The Chromium-family browsers need nothing here: their tint comes from the
# theme's chromium.theme, which the theme ships with a light seed (see
# playbooks/omaraptor-themes.yml).

# The whole family also uses Bluefin's default GTK4/libadwaita accent, slate
# (the gray one), instead of GNOME's stock blue. Omarchy never touches
# accent-color, so it is set here for all three themes. Any other theme gets
# the stock blue back, but only if the accent is still the slate set here.

# gsettings needs a user DBus session (absent e.g. during ISO installs).
[[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || exit 0

case $1 in
  omaraptor)
    gsettings set org.gnome.desktop.interface color-scheme "prefer-light"
    gsettings set org.gnome.desktop.interface gtk-theme "Adwaita"
    gsettings set org.gnome.desktop.interface accent-color "slate"
    ;;
  omaraptor[-_]light | omaraptor[-_]dark)
    gsettings set org.gnome.desktop.interface accent-color "slate"
    ;;
  *)
    if [[ $(gsettings get org.gnome.desktop.interface accent-color) == "'slate'" ]]; then
      gsettings set org.gnome.desktop.interface accent-color "blue"
    fi
    ;;
esac
