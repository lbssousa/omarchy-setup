#!/usr/bin/bash
# Two independent detectors, run in parallel, that both restart fprintd
# when they see a signature that leaves fingerprint unlock stuck for
# the rest of the lock session instead of a single failed attempt.
set -uo pipefail

RESTART_COOLDOWN=10

# A burst this large is far above a healthy locked session (~2
# fingerprint attempts/minute, per omacom/omarchy#7176) and comfortably
# below the failure cascade itself (~4/s, sustained for as long as the
# screen stays locked).
BURST_THRESHOLD=8
BURST_WINDOW=5

restart_fprintd() {
  echo "fprintd-desync-watchdog: restarting fprintd ($1)"
  systemctl restart fprintd.service
  sleep "$RESTART_COOLDOWN"
}

# The goodix538d driver can desync its protocol with the sensor's MCU
# after a verify cancel, leaving fprintd stuck failing every subsequent
# verify instantly instead of waiting for a touch.
watch_desync() {
  journalctl -u fprintd -f -n0 -o cat \
    | grep --line-buffered -E 'Invalid (ACK|protocol) command' \
    | while read -r _; do
        restart_fprintd "goodix538d protocol desync"
      done
}

# The Omarchy lock screen retries fingerprint auth on a flat 250ms
# timer with no backoff, regardless of *why* the previous attempt
# failed (upstream omacom/omarchy#7176, #7172 — open, unfixed as of
# Omarchy 4.0.1). A device-level failure (thermal throttle, a wedged
# exclusive claim after suspend, ...) returns instantly and
# identically every time, so the loop hammers fprintd for as long as
# the screen stays locked instead of backing off. Restarting fprintd
# clears the wedged/throttled state — the same manual fix reported
# upstream.
watch_retry_storm() {
  journalctl -o cat -t omarchy-shell -f -n0 \
    | grep --line-buffered -E 'Starting pam session for user .* config "omarchy-lock-fingerprint"' \
    | awk -v threshold="$BURST_THRESHOLD" -v window="$BURST_WINDOW" '
        {
          now = systime()
          times[++count] = now
          while (head < count && times[head + 1] < now - window) {
            delete times[head + 1]
            head++
          }
          if (count - head >= threshold) {
            print "burst"
            fflush()
            head = count
          }
        }
      ' \
    | while read -r _; do
        restart_fprintd "lock screen fingerprint retry storm"
      done
}

watch_desync &
watch_retry_storm &
wait -n
