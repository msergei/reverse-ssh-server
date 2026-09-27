# reverse-ssh-server

Publish a service from a host without incoming ports (client) on a LAN port of
another host (server) through a reverse SSH tunnel.

```
LAN user ──▶ server 192.168.10.53:13000 ─┐
                                         │ ssh -R (client dials out to server:34051)
client:  127.0.0.1:3001 (e.g. Firefox) ◀─┘
```

The server only runs a locked-down sshd; the client dials out, so it needs no
open ports. The published port is bound to the server's LAN address only.

## Security model

The previous version (root login with a password passed via `sshpass`,
`StrictHostKeyChecking=no`, `GatewayPorts yes`, Ubuntu 14.04) got a server
compromised. Now:

- **Keys only**, ed25519 only, a single unprivileged `tunnel` user.
- **sshd runs as non-root** in a read-only container with all capabilities
  dropped; no shell, no TTY, no agent/X11 forwarding.
- The key may only do `-R 0.0.0.0:13000` and `-L 127.0.0.1:13000`
  (both in `sshd_config` and as `authorized_keys` options).
- **Pinned server host key** on the client, so no trust-on-first-use.
- Published port bound to `LAN_BIND` only. Never forward it on the router.
- Secrets live only in `.env` files (git-ignored). The client private key is
  generated on the client and never leaves it.

## Hangs / watchdog

- Client: `ServerAliveInterval=10`, `ServerAliveCountMax=3`: a dead
  connection is dropped in about 30s, and the loop reconnects.
- Server: `ClientAliveInterval=10`, `ClientAliveCountMax=3`: a stale session
  can't keep port 13000 busy (in the old version a new connection then failed
  with "remote port forwarding failed").
- `watchdog` service (client): every 30s it requests the service **through the
  whole loop** (client → server:13000 → client) over an extra `-L` in the same
  SSH connection. After 3 failures it kills ssh, and the tunnel reconnects. If
  the service itself is down, it leaves the tunnel alone. It shares the
  tunnel's PID namespace, so it doesn't need the docker socket.

## Server

```bash
cd server
cp .env.example .env   # set LAN_BIND, AUTHORIZED_KEYS
docker compose up -d --build
docker compose logs | grep ssh-ed25519   # host key → client SERVER_HOST_KEY
```

On the router, forward `SSH_PORT` (34051) TCP to the server. **Only that one.**

## Client

```bash
cd client
cp .env.example .env
ssh-keygen -t ed25519 -N "" -C "$(hostname)-tunnel" -f /tmp/k
base64 < /tmp/k | tr -d '\n'   # → SSH_PRIVATE_KEY_B64
cat /tmp/k.pub                 # → server AUTHORIZED_KEYS
rm /tmp/k /tmp/k.pub
# set SERVER_HOST, SERVER_HOST_KEY, TARGET_PORT, BROWSER_PASSWORD
docker compose up -d --build
```

`docker-compose.browser.yml` adds Firefox (linuxserver, HTTPS with a
self-signed cert and basic auth) on `127.0.0.1:${TARGET_PORT}`. Remove it from
`COMPOSE_FILE` in `.env` to tunnel some other local service. For a non-HTTP
service, set `CHECK_MODE=tcp` (the watchdog then can't detect a broken loop,
only reconnects on SSH keepalive failures).

Open `https://<LAN_BIND>:<LAN_PORT>/` from the LAN.

## Logs

```bash
docker compose logs -f           # client: tunnel + watchdog
docker compose ps                # tunnel health = end-to-end check
```
