# reverse-ssh-server

Publish a service from a host without incoming ports (client) on a LAN port of
another host (server) through a reverse SSH tunnel.

```
LAN user ──▶ server 192.168.10.53:13000 ─┐
                                         │ ssh -R (client dials out to server:34051)
client:  browser:3001 (Chromium)       ◀─┘
```

The server only runs a locked-down sshd; the client dials out, so it needs no
open ports. The published port is bound to the server's LAN address only. On
the client the service has no port on the host either: the tunnel reaches it
over the compose network.

## Security model

The previous version (root login with a password passed via `sshpass`,
`StrictHostKeyChecking=no`, `GatewayPorts yes`, Ubuntu 14.04) got a server
compromised. Now:

- **Keys only**, ed25519 only, a single unprivileged `tunnel` user.
- **sshd runs as non-root** in a read-only container with all capabilities
  dropped; no shell, no TTY, no agent/X11 forwarding.
- The key may only do `-R 0.0.0.0:13000` and `-L 127.0.0.1:13000`
  (both in `sshd_config` and as `authorized_keys` options).
- **No outgoing connections from the server container**: at start the
  entrypoint loads an nftables policy (`egress.nft`) into the container's
  network namespace, then drops to `tunnel` with no capabilities left. Even an
  sshd exploit can't reach the LAN, the host or the internet (e.g. to fetch a
  miner). The container is also capped at 1 CPU (the tunnel needs ~3%).
- On the client the private key is removed from the tunnel process
  environment after it is written to a tmpfs file.
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
docker compose build --pull && docker compose up -d
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
docker compose build --pull && docker compose up -d
```

`docker-compose.browser.yml` adds Chromium (linuxserver, Selkies stream over
HTTPS with a
self-signed cert and basic auth) as `browser:3001` on the compose network, with
no port on the host. To tunnel some other service instead, remove it from
`COMPOSE_FILE` in `.env` and set `TARGET_HOST`/`TARGET_PORT`: a compose service
name, or `host.docker.internal` for a service of the host (it must listen on
`0.0.0.0` or the docker bridge). For a non-HTTP service, set `CHECK_MODE=tcp`
(the watchdog then can't detect a broken loop, only reconnects on SSH
keepalive failures).

Open `https://<LAN_BIND>:<LAN_PORT>/` from the LAN.

Russian Trusted Root/Sub CA (Mintsifry, from `gu-st.ru/content/downloads/`,
in `certs/`): Chromium takes locally added roots from the profile's NSS db only
(the `CACertificates` policy has no effect in this build). Run once, after the
first `up`; the db lives in the volume:

```bash
./chromium-certs.sh   # throwaway Debian container with certutil
docker compose restart browser
```

Root SHA-256:
`D2:6D:2D:02:31:B7:C3:9F:92:CC:73:85:12:BA:54:10:35:19:E4:40:5D:68:B5:BD:70:3E:97:88:CA:8E:CF:31`.
The browser trusts this root for every domain, not only Russian ones: use it
for those sites only.

### Raspberry Pi 4

Add `docker-compose.browser-rpi.yml` to `COMPOSE_FILE`: Selkies then encodes
on the Pi's hardware H.264 encoder (`/dev/video11`, V4L2 M2M) instead of x264,
~0.15 of a core instead of ~1.1. `rpi-init/` grants the container user that
device. Measured on a Pi 4 (4 GB, 1.5 GHz) on a heavy site, whole CPU:

| setup | CPU |
| --- | --- |
| Firefox, Selkies, x264 | ~100% (saturated) |
| Firefox, Selkies, hardware H.264 | ~50-75% |
| Chromium, KasmVNC, rendering on V3D | ~50-75% |
| **Chromium, Selkies, hardware H.264** | **~30-40%** |

GPU rendering doesn't pay off: with `/dev/dri` the Selkies compositor renders
on V3D and loses the hardware encoder (pixelflux reads frames back and tries
only VA-API), and without a GPU compositor the browser gets no dmabuf and
renders in software anyway. What's left is the page's JavaScript on one core;
only a higher clock helps there.

The stream is capped at 20 FPS with CSS scaling (a Retina client gets its
logical resolution, not 3456x2160), see `BROWSER_CSS_SCALING` and
`BROWSER_FRAMERATE`.

## Logs

```bash
docker compose logs -f           # client: tunnel + watchdog
docker compose ps                # tunnel health = end-to-end check
```

## Updates

Rebuild both sides regularly: `--pull` fetches the latest Alpine patch release
(and with it OpenSSH fixes), a plain `--build` reuses the cached base image.

```bash
docker compose build --pull && docker compose up -d   # server and client
docker compose pull browser && docker compose up -d   # client: Chromium
```
