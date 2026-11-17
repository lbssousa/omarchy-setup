#!/bin/bash
# Keep the Omarchy bar (and other top-layer surfaces) hidden under the screensaver.
#
# Hyprland only fades top-layer surfaces when a window goes fullscreen. If the
# bar's layer surface is (re)mapped while the screensaver is already up -- shell
# reload, screen remap, etc. -- it is drawn above the fullscreen screensaver.
# Re-applying the screensaver's fullscreen state makes Hyprland hide it again.

CLASS=org.omarchy.screensaver
SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

refullscreen() {
  local addr
  for addr in $(hyprctl clients -j | jq -r --arg c "$CLASS" '.[] | select(.class == $c and .mapped) | .address'); do
    hyprctl dispatch "hl.dsp.window.fullscreen_state({ window = \"address:$addr\", internal = 0, client = 0 })" >/dev/null
    hyprctl dispatch "hl.dsp.window.fullscreen_state({ window = \"address:$addr\", internal = 2, client = 2 })" >/dev/null
  done
}

while true; do
  socat -U - "UNIX-CONNECT:$SOCKET" | while IFS= read -r line; do
    case $line in
    openlayer\>\>omarchy-bar | openlayer\>\>omarchy-dock)
      sleep 0.2
      refullscreen
      ;;
    esac
  done
  sleep 1
done
