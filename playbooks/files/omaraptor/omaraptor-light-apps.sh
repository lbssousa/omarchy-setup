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
# shade from @accent_bg_color). GTK3 apps (Firefox) read the same override from
# ~/.config/gtk-3.0/gtk.css, as @theme_selected_bg_color.
#
# Flatpak apps (Bazaar, Firefox, ...) can't see either file unless the sandbox
# is given the directories: playbooks/omaraptor-themes.yml sets a user-wide
# `--filesystem=xdg-config/gtk-{3,4}.0:ro` override for that.

# gsettings needs a user DBus session (absent e.g. during ISO installs).
[[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || exit 0

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
GTK3_CSS="$CONFIG/gtk-3.0/gtk.css"
GTK4_CSS="$CONFIG/gtk-4.0/gtk.css"
BEGIN="/* >>> omaraptor accent (managed by omarchy-setup) >>> */"
END="/* <<< omaraptor accent <<< */"

# Drop the managed block from the file in $1, and the file if nothing else
# is left in it.
remove_block() {
  local css=$1 rest
  [[ -f $css ]] || return 0
  rest=$(awk -v b="$BEGIN" -v e="$END" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$css")
  if [[ -z ${rest//[[:space:]]/} ]]; then
    rm -f "$css"
  else
    printf '%s\n' "$rest" >"$css"
  fi
}

remove_css_accent() {
  remove_block "$GTK3_CSS"
  remove_block "$GTK4_CSS"
}

set_css_accent() {
  remove_css_accent
  mkdir -p "$(dirname "$GTK3_CSS")" "$(dirname "$GTK4_CSS")"
  cat >>"$GTK4_CSS" <<CSS
$BEGIN
@define-color accent_bg_color #6f8396;
@define-color accent_fg_color #ffffff;
$END
CSS
  cat >>"$GTK3_CSS" <<CSS
$BEGIN
@define-color theme_selected_bg_color #6f8396;
@define-color theme_selected_fg_color #ffffff;
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
