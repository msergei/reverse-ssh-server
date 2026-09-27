FROM alpine:3.24

RUN apk add --no-cache openssh-server nftables setpriv && \
    adduser -D -H -u 10022 -s /sbin/nologin tunnel && \
    sed -i 's/^tunnel:!/tunnel:*/' /etc/shadow && \
    mkdir -p /data && chown tunnel:tunnel /data && chmod 700 /data

COPY sshd_config /etc/ssh/sshd_config
COPY egress.nft /etc/egress.nft
COPY entrypoint.sh /entrypoint.sh

# Starts as root only to load the egress firewall, then entrypoint.sh drops to
# the "tunnel" user with no capabilities: only "tunnel" can log in, and a sshd
# compromise yields no root inside the container.
EXPOSE 2222

ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
