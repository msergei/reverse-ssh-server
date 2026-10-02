#!/bin/sh
# check.sh target|loop — exit 0 if the service answers.
#   target: the service directly (TARGET_HOST:TARGET_PORT)
#   loop:   through client -> server:13000 -> back to the service (CHECK_PORT)
# CHECK_MODE=http: expects any HTTP(S) response; tcp: connection accepted
# (tcp can't tell a broken loop, since the local -L listener always accepts).
: "${TARGET_HOST:=host.docker.internal}" "${CHECK_PORT:=13001}" "${CHECK_MODE:=http}" "${CHECK_SCHEME:=https}"

case "$1" in
    target) host=$TARGET_HOST; port=$TARGET_PORT ;;
    loop)   host=127.0.0.1;    port=$CHECK_PORT ;;
    *) echo "usage: $0 target|loop" >&2; exit 2 ;;
esac

if [ "$CHECK_MODE" = tcp ]; then
    nc -z -w 5 "$host" "$port"
else
    # --insecure: the service usually has a self-signed cert; any status code is
    # fine. Judge by the status, not curl's exit: KasmVNC drops TLS without a
    # close_notify after answering, so curl exits 56 on a healthy service.
    code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "$CHECK_SCHEME://$host:$port/")
    [ "${code:-000}" != 000 ]
fi
