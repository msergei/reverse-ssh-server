#!/bin/sh
# Trust the Russian CAs in Chromium: it reads locally added roots from the
# profile's NSS db (~/.pki/nssdb); the CACertificates policy has no effect in
# this build. The image has no certutil, so a throwaway Debian container
# writes the db into the volume. Run once from client/; the db persists.
# Usage: ./chromium-certs.sh [volume]  (the volume holds the user's home)
set -e
docker run --rm -v "${1:-reverse-ssh-client_browser-chromium}:/config" -v "$PWD/certs:/certs:ro" \
  debian:trixie-slim sh -c '
    apt-get update -qq >/dev/null && apt-get install -y -qq libnss3-tools >/dev/null
    db=sql:/config/.pki/nssdb
    mkdir -p /config/.pki/nssdb
    [ -f /config/.pki/nssdb/cert9.db ] || certutil -d $db -N --empty-password
    for f in /certs/*.cer; do
      n=$(basename "$f" .cer)
      case $n in *Root*) t=C,,;; *) t=,,;; esac
      certutil -d $db -A -t "$t" -n "$n" -i "$f"
    done
    certutil -d $db -L
    chown -R 1000:1000 /config/.pki'
