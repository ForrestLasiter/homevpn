#!/usr/bin/env bash
#
# duckdns-update.sh — point <domain>.duckdns.org at this box's public IP.
# Called by the duckdns.timer every 5 minutes. Reads /etc/duckdns.env
# (DUCKDNS_DOMAIN, DUCKDNS_TOKEN). Safe to run by hand to test.

set -euo pipefail

: "${DUCKDNS_DOMAIN:?set DUCKDNS_DOMAIN}"
: "${DUCKDNS_TOKEN:?set DUCKDNS_TOKEN}"

# Empty ip= makes DuckDNS use the source IP of the request (our public IP).
RESP="$(curl -fsS "https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip=")"

if [[ "$RESP" == "OK" ]]; then
  logger -t duckdns "updated ${DUCKDNS_DOMAIN}.duckdns.org OK"
  echo "OK — ${DUCKDNS_DOMAIN}.duckdns.org updated."
else
  logger -t duckdns "update FAILED: ${RESP}"
  echo "FAILED — DuckDNS returned: ${RESP}" >&2
  exit 1
fi
