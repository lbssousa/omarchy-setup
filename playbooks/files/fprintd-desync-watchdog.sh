#!/usr/bin/bash
# Restarts fprintd when the goodix538d driver desyncs its protocol with the
# sensor's MCU after a verify cancel: fprintd then fails every later verify
# instantly instead of waiting for a touch, for the rest of the lock
# session. (The lock screen's own retry loop is Omarchy's business since
# 4.5: it backs off and restarts fprintd on resume.)
set -uo pipefail

RESTART_COOLDOWN=10

journalctl -u fprintd -f -n0 -o cat \
  | grep --line-buffered -E 'Invalid (ACK|protocol) command' \
  | while read -r _; do
      echo "fprintd-desync-watchdog: restarting fprintd (goodix538d protocol desync)"
      systemctl restart fprintd.service
      sleep "$RESTART_COOLDOWN"
    done
