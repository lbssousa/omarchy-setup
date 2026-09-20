#!/bin/bash

# Omarchy `theme-set` hook, installed as
# ~/.config/omarchy/hooks/theme-set.d/omadwaita-light-apps. It is called
# with the snake-cased name of the theme that was just set.
#
# The "Omadwaita" theme has a dark TUI palette (colors.toml: mode = "dark")
# but light GUI apps. Omarchy derives both GUI settings from that dark
# palette, so by the time this hook runs it has already set:
#
#   - GTK to Adwaita-dark + prefer-dark (omarchy-theme-set-gnome), and
#   - the Chromium-family browser policy's BrowserThemeColor to the
#     theme's dark background (omarchy-theme-set-browser). Chromium, Brave,
#     Chrome and Edge tint their tab strip and toolbar from that color, not
#     from the light/dark scheme, so they'd stay dark even under light GTK.
#
# Put both back to light. Every other theme is left alone: setting one of
# them re-runs both of Omarchy's own steps, restoring GTK and the browser
# color to that theme's own values.

[[ $1 == omadwaita ]] || exit 0

# gsettings needs a user DBus session (absent e.g. during ISO installs).
if [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
  gsettings set org.gnome.desktop.interface color-scheme "prefer-light"
  gsettings set org.gnome.desktop.interface gtk-theme "Adwaita"
fi

# Same color as Omadwaita Light's background (view_bg_color). Running
# browsers pick the policy change up on their own; no restart needed.
omarchy-theme-set-browser-policy ffffff
