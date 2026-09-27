#!/bin/sh
set -eu

if [ "$(id -u)" = 0 ]; then
    # Fails closed: without the firewall the container exits instead of serving
    nft -f /etc/egress.nft
    # Continue as the tunnel user with every capability dropped
    exec setpriv --reuid=tunnel --regid=tunnel --clear-groups \
        --inh-caps=-all --bounding-set=-all -- /bin/sh "$0" "$@"
fi

if [ -z "${AUTHORIZED_KEYS:-}" ]; then
    echo "AUTHORIZED_KEYS is empty, refusing to start" >&2
    exit 1
fi

HOST_KEY=/data/ssh_host_ed25519_key
if [ ! -f "$HOST_KEY" ]; then
    echo "=> Generating host key"
    ssh-keygen -q -t ed25519 -N "" -C "reverse-ssh-server" -f "$HOST_KEY"
fi
echo "=> Host key (put into client SERVER_HOST_KEY):"
cut -d' ' -f1,2 "$HOST_KEY.pub"

# Per-key restrictions on top of sshd_config: forwarding only, fixed ports.
OPTS='restrict,port-forwarding,permitlisten="0.0.0.0:13000",permitopen="127.0.0.1:13000"'
AK=/run/tunnel/authorized_keys
: > "$AK"
echo "$AUTHORIZED_KEYS" | tr ',' '\n' | while read -r key; do
    [ -n "$key" ] && echo "$OPTS $key" >> "$AK"
done
chmod 600 "$AK"
echo "=> Authorized keys: $(wc -l < "$AK")"

exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config
