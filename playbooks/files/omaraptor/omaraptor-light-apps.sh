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
# accent-color, so this hook sets it for all three themes.
#
# Setting org.gnome.desktop.interface accent-color is not enough here:
# libadwaita reads the accent from the XDG Settings portal, and
# xdg-desktop-portal-gtk (the Settings backend outside GNOME) does not expose
# it, so libadwaita would fall back to blue. The slate accent is therefore also
# written as a CSS override in ~/.config/gtk-4.0/gtk.css, inside a marked block
# that any other theme removes again (libadwaita derives every other accent
# shade from @accent_bg_color).

# gsettings needs a user DBus session (absent e.g. during ISO installs).
[[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || exit 0

GTK4_CSS="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/gtk.css"
BEGIN="/* >>> omaraptor accent (managed by omarchy-setup) >>> */"
END="/* <<< omaraptor accent <<< */"

# Drop the managed block, and the file if nothing else is left in it.
remove_css_accent() {
  [[ -f $GTK4_CSS ]] || return 0
  local rest
  rest=$(awk -v b="$BEGIN" -v e="$END" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$GTK4_CSS")
  if [[ -z ${rest//[[:space:]]/} ]]; then
    rm -f "$GTK4_CSS"
  else
    printf '%s\n' "$rest" >"$GTK4_CSS"
  fi
}

set_css_accent() {
  remove_css_accent
  mkdir -p "$(dirname "$GTK4_CSS")"
  cat >>"$GTK4_CSS" <<CSS
$BEGIN
@define-color accent_bg_color #6f8396;
@define-color accent_fg_color #ffffff;
$END
CSS
}

case $1 in
  omaraptor)
    gsettings set org.gnome.desktop.interface color-scheme "prefer-light"
    gsettings set org.gnome.desktop.interface gtk-theme "Adwaita"
    gsettings set org.gnome.desktop.interface accent-color "slate"
    set_css_accent
    ;;
  omaraptor[-_]light | omaraptor[-_]dark)
    gsettings set org.gnome.desktop.interface accent-color "slate"
    set_css_accent
    ;;
  *)
    if [[ $(gsettings get org.gnome.desktop.interface accent-color) == "'slate'" ]]; then
      gsettings set org.gnome.desktop.interface accent-color "blue"
    fi
    remove_css_accent
    ;;
esac
