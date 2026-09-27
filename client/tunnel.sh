#!/bin/sh
# Keeps a reverse tunnel up: SERVER:13000 -> TARGET_HOST:TARGET_PORT.
# Also opens 127.0.0.1:CHECK_PORT -> SERVER:13000 over the same connection,
# so the watchdog can test the whole loop end to end.
set -eu

: "${SERVER_HOST:?}" "${SERVER_PORT:?}" "${SERVER_HOST_KEY:?}" "${SSH_PRIVATE_KEY_B64:?}"
: "${TARGET_HOST:=127.0.0.1}" "${TARGET_PORT:?}" "${CHECK_PORT:=13001}" "${RETRY_DELAY:=10}"

log() { echo "$(date '+%F %T') tunnel: $*"; }

D=/run/tunnel
echo "$SSH_PRIVATE_KEY_B64" | base64 -d > "$D/id_ed25519"
chmod 600 "$D/id_ed25519"
# Pinned server key: no trust-on-first-use, no silent MITM
if [ "$SERVER_PORT" = 22 ]; then HK="$SERVER_HOST"; else HK="[$SERVER_HOST]:$SERVER_PORT"; fi
echo "$HK $SERVER_HOST_KEY" > "$D/known_hosts"

while true; do
    log "connecting to $SERVER_HOST:$SERVER_PORT"
    ssh -N -F /dev/null \
        -i "$D/id_ed25519" -o IdentitiesOnly=yes -o BatchMode=yes \
        -o UserKnownHostsFile="$D/known_hosts" -o StrictHostKeyChecking=yes \
        -o ExitOnForwardFailure=yes \
        -o ConnectTimeout=15 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 \
        -o TCPKeepAlive=yes \
        -R "0.0.0.0:13000:$TARGET_HOST:$TARGET_PORT" \
        -L "127.0.0.1:$CHECK_PORT:127.0.0.1:13000" \
        -p "$SERVER_PORT" "tunnel@$SERVER_HOST" || true
    log "disconnected, retry in ${RETRY_DELAY}s"
    sleep "$RETRY_DELAY"
done
