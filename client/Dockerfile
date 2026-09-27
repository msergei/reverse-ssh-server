FROM alpine:3.22

RUN apk add --no-cache openssh-client curl && \
    adduser -D -H -u 10022 -s /sbin/nologin tunnel

COPY --chmod=755 tunnel.sh watchdog.sh check.sh /usr/local/bin/

USER tunnel
ENV HOME=/run/tunnel

ENTRYPOINT ["/bin/sh", "/usr/local/bin/tunnel.sh"]
