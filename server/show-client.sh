#!/usr/bin/env bash
#
# show-client.sh — re-print a device's config and QR code
# ------------------------------------------------------------------
# RUN INSIDE THE HUB CONTAINER.   ./show-client.sh <name> [--qr-only]
# Handy when you're adding the device to a second phone/tablet, or lost
# the original output.

set -euo pipefail
die() { echo -e "\033[1;31m[x]\033[0m $*" >&2; exit 1; }

NAME="${1:-}"
[[ -n "$NAME" ]] || die "Usage: $0 <name> [--qr-only]"
CONF="/etc/wireguard/clients/${NAME}.conf"
[[ -f "$CONF" ]] || die "No client named '$NAME' (looked for $CONF). Try: ./list-clients.sh"

if [[ "${2:-}" != "--qr-only" ]]; then
  echo "----- ${NAME}.conf -----"
  cat "$CONF"
  echo "------------------------"
  echo
fi

command -v qrencode >/dev/null || die "qrencode not installed (apt install qrencode)."
echo "Scan with the WireGuard app:"
qrencode -t ansiutf8 < "$CONF"
