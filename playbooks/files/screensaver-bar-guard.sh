#!/bin/bash
# Keep the Omarchy bar (and other top-layer surfaces) hidden under the screensaver.
#
# Hyprland only fades top-layer surfaces when a window goes fullscreen. If the
# bar's layer surface is (re)mapped while the screensaver is already up -- shell
# reload, screen remap, etc. -- it is drawn above the fullscreen screensaver.
# Re-applying the screensaver's fullscreen state makes Hyprland hide it again.
#
# Diagnostics (temporary): while a screensaver is open, every Hyprland event is
# logged to $LOG, and a capture of the bar strip is saved 5s and 60s after it
# opens, to find what else brings the bar back.

CLASS=org.omarchy.screensaver
SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/screensaver-bar-guard"
LOG="$STATE/events.log"
mkdir -p "$STATE"

log() { printf '%s %s\n' "$(date '+%F %T.%3N')" "$*" >>"$LOG"; }

refullscreen() {
  local addr
  for addr in $(hyprctl clients -j | jq -r --arg c "$CLASS" '.[] | select(.class == $c and .mapped) | .address'); do
    log "guard: refullscreen $addr ($1)"
    hyprctl dispatch "hl.dsp.window.fullscreen_state({ window = \"address:$addr\", internal = 0, client = 0 })" >/dev/null
    hyprctl dispatch "hl.dsp.window.fullscreen_state({ window = \"address:$addr\", internal = 2, client = 2 })" >/dev/null
  done
}

snapshot() {
  local delay=$1 stamp=$2
  sleep "$delay"
  hyprctl clients -j | jq -e --arg c "$CLASS" 'any(.[]; .class == $c and .mapped)' >/dev/null || return
  local file="$STATE/bar-$stamp-${delay}s.png" geometry
  # The top 60 logical pixels of every monitor, side by side as grim sees them.
  while read -r geometry; do
    grim -g "$geometry" -s 0.5 "${file%.png}-${geometry%% *}.png"
  done < <(hyprctl monitors -j | jq -r '.[] | "\(.x),\(.y) \((.width / .scale) | floor)x60"')
  log "guard: snapshot ${file%.png}-*.png"
}

# Keep the log small.
[[ -f $LOG ]] && (( $(stat -c %s "$LOG") > 1048576 )) && mv -f "$LOG" "$LOG.old"
find "$STATE" -name 'bar-*.png' -mtime +7 -delete 2>/dev/null

open=0
while true; do
  while IFS= read -r line; do
    case $line in
    openwindow\>\>*",$CLASS,"*)
      open=$((open + 1))
      log "$line"
      stamp=$(date +%Y%m%d-%H%M%S)
      snapshot 5 "$stamp" &
      snapshot 60 "$stamp" &
      continue
      ;;
    closewindow\>\>*)
      if ((open > 0)) && ! hyprctl clients -j | jq -e --arg c "$CLASS" 'any(.[]; .class == $c and .mapped)' >/dev/null; then
        log "$line (screensaver gone)"
        open=0
        continue
      fi
      ;;
    esac

    ((open > 0)) && [[ $line != mousemove* ]] && log "$line"

    case $line in
    openlayer\>\>omarchy-bar | openlayer\>\>omarchy-dock)
      sleep 0.2
      refullscreen "$line"
      ;;
    esac
  done < <(socat -U - "UNIX-CONNECT:$SOCKET")
  sleep 1
done
