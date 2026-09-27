#!/bin/sh
# Catches a tunnel that looks alive but no longer forwards (hung channel,
# half-open TCP that keepalives miss, remote listener lost, ...).
# Shares the tunnel container's PID namespace and kills its ssh; the tunnel
# loop then reconnects.
set -u
: "${WATCHDOG_INTERVAL:=30}" "${WATCHDOG_MAX_FAILS:=3}" "${WATCHDOG_START_DELAY:=60}"

log() { echo "$(date '+%F %T') watchdog: $*"; }

log "started: every ${WATCHDOG_INTERVAL}s, kill ssh after ${WATCHDOG_MAX_FAILS} failed checks"
sleep "$WATCHDOG_START_DELAY"
fails=0
while true; do
    if check.sh loop; then
        [ "$fails" -gt 0 ] && log "loop ok again"
        fails=0
    elif ! check.sh target; then
        # Service itself is down: restarting the tunnel won't help
        log "target $TARGET_HOST:$TARGET_PORT is down, not touching the tunnel"
        fails=0
    else
        fails=$((fails + 1))
        log "loop check failed ($fails/$WATCHDOG_MAX_FAILS)"
        if [ "$fails" -ge "$WATCHDOG_MAX_FAILS" ]; then
            log "restarting tunnel (killing ssh)"
            pkill -x ssh || log "no ssh process found"
            fails=0
            sleep "$WATCHDOG_START_DELAY"
        fi
    fi
    sleep "$WATCHDOG_INTERVAL"
done
