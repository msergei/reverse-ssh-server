FROM alpine:3.22

RUN apk add --no-cache openssh-server && \
    adduser -D -H -u 10022 -s /sbin/nologin tunnel && \
    sed -i 's/^tunnel:!/tunnel:*/' /etc/shadow && \
    mkdir -p /data && chown tunnel:tunnel /data && chmod 700 /data

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /entrypoint.sh

# sshd runs unprivileged: only the "tunnel" user can log in, and a sshd
# compromise yields no root inside the container.
USER tunnel
EXPOSE 2222

ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
