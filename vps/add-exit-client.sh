#!/usr/bin/env bash
#
# add-exit-client.sh — enroll a device on the VPS exit node
# ------------------------------------------------------------------
# RUN THIS ON THE VPS, as root, AFTER bootstrap-exit.sh.
#
#   ./add-exit-client.sh <name>
#
# Produces a full-tunnel config: ALL the device's traffic exits from the
# VPS's IP. That's the whole point of Phase 2 — a not-your-house exit.
# Prints a QR for phones, just like the home hub's add-client.sh.

set -euo pipefail
msg() { echo -e "\033[1;32m[+]\033[0m $*"; }
die() { echo -e "\033[1;31m[x]\033[0m $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Run as root."
[[ -f /etc/wireguard/exit.env ]] || die "Run bootstrap-exit.sh first."
# shellcheck disable=SC1091
source /etc/wireguard/exit.env

NAME="${1:-}"
[[ -n "$NAME" ]] || die "Usage: $0 <name>"
[[ "$NAME" =~ ^[A-Za-z0-9_-]+$ ]] || die "Name: letters/numbers/-/_ only."

CONF="/etc/wireguard/${EXIT_IF}.conf"
OUTDIR="/etc/wireguard/clients"; install -d -m 700 "$OUTDIR"
CLIENT_CONF="${OUTDIR}/${NAME}.conf"
[[ -e "$CLIENT_CONF" ]] && die "Client '$NAME' already exists."

[[ -n "${EXIT_ENDPOINT:-}" ]] || EXIT_ENDPOINT="$(curl -s https://api.ipify.org)"
[[ -n "$EXIT_ENDPOINT" ]] || die "No endpoint known — set EXIT_ENDPOINT in config.env."

BASE="${EXIT_ADDR%.*}"
USED="$(grep -oE "${BASE//./\\.}\.[0-9]+" "$CONF" 2>/dev/null | awk -F. '{print $4}' | sort -n | uniq || true)"
NEXT=""
for i in $(seq 2 254); do grep -qx "$i" <<<"$USED" || { NEXT="$i"; break; }; done
[[ -n "$NEXT" ]] || die "No free addresses in ${EXIT_SUBNET}."
CLIENT_IP="${BASE}.${NEXT}"

umask 077
CLIENT_PRIV="$(wg genkey)"; CLIENT_PUB="$(wg pubkey <<<"$CLIENT_PRIV")"; CLIENT_PSK="$(wg genpsk)"

cat > "$CLIENT_CONF" <<EOF
# ${NAME}  (VPS exit, full-tunnel)  — generated $(date -u +%FT%TZ)
[Interface]
PrivateKey = ${CLIENT_PRIV}
Address    = ${CLIENT_IP}/32
DNS        = ${CLIENT_DNS:-1.1.1.1}

[Peer]
PublicKey           = ${EXIT_PUB}
PresharedKey        = ${CLIENT_PSK}
Endpoint            = ${EXIT_ENDPOINT}:${EXIT_PORT}
AllowedIPs          = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
chmod 600 "$CLIENT_CONF"

cat >> "$CONF" <<EOF

[Peer]
# ${NAME} (exit)
PublicKey    = ${CLIENT_PUB}
PresharedKey = ${CLIENT_PSK}
AllowedIPs   = ${CLIENT_IP}/32
EOF
wg syncconf "$EXIT_IF" <(wg-quick strip "$EXIT_IF")

echo
msg "Added '${NAME}' -> ${CLIENT_IP}  (exits via ${EXIT_ENDPOINT})"
echo "Config: ${CLIENT_CONF}"
echo
echo "Scan with the WireGuard app:"
qrencode -t ansiutf8 < "$CLIENT_CONF"
echo
echo "Tip: keep this AND your home config as two tunnels on the device —"
echo "     flip to this one when you want the not-your-house exit."
