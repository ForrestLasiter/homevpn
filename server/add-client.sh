#!/usr/bin/env bash
#
# add-client.sh — enroll a device on the WireGuard hub
# ------------------------------------------------------------------
# RUN THIS INSIDE THE HUB CONTAINER, as root, AFTER bootstrap.sh.
#
#   ./add-client.sh <name> [full|split]
#
#     name   a label for the device        (e.g. pixel, iphone, laptop)
#     full   (default) route ALL traffic through home  -> privacy on
#            untrusted Wi-Fi, home IP is the exit
#     split  route ONLY the VPN + home LAN through the tunnel; normal
#            internet goes out the device's own connection
#
# It picks the next free VPN IP, adds the peer to the live tunnel and
# to wg0.conf, writes clients/<name>.conf, and prints a QR code you can
# scan straight into the WireGuard phone app.

set -euo pipefail

msg()  { echo -e "\033[1;32m[+]\033[0m $*"; }
die()  { echo -e "\033[1;31m[x]\033[0m $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root."
[[ -f /etc/wireguard/hub.env ]] || die "Run bootstrap.sh first (missing /etc/wireguard/hub.env)."
# shellcheck disable=SC1091
source /etc/wireguard/hub.env

NAME="${1:-}"
MODE="${2:-full}"
[[ -n "$NAME" ]]        || die "Usage: $0 <name> [full|split]"
[[ "$NAME" =~ ^[A-Za-z0-9_-]+$ ]] || die "Name must be letters/numbers/-/_ only."
[[ "$MODE" == full || "$MODE" == split ]] || die "Mode must be 'full' or 'split'."

CONF="/etc/wireguard/${WG_IF}.conf"
OUTDIR="/etc/wireguard/clients"
install -d -m 700 "$OUTDIR"
CLIENT_CONF="${OUTDIR}/${NAME}.conf"
[[ -e "$CLIENT_CONF" ]] && die "A client named '$NAME' already exists ($CLIENT_CONF). Pick another name or delete it."

# --- endpoint the client dials home on -------------------------------
if [[ -n "${DUCKDNS_DOMAIN}" ]]; then
  ENDPOINT_HOST="${DUCKDNS_DOMAIN}.duckdns.org"
else
  ENDPOINT_HOST="$(curl -s https://api.ipify.org || true)"
  [[ -n "$ENDPOINT_HOST" ]] || die "No DuckDNS domain set and couldn't detect public IP. Set DUCKDNS_DOMAIN in bootstrap."
fi
ENDPOINT="${ENDPOINT_HOST}:${WG_PORT}"

# --- next free VPN address (start at .2) ------------------------------
BASE="${WG_ADDR%.*}"            # 10.10.10
USED="$(grep -oE "${BASE//./\\.}\.[0-9]+" "$CONF" 2>/dev/null | awk -F. '{print $4}' | sort -n | uniq || true)"
NEXT=""
for i in $(seq 2 254); do
  if ! grep -qx "$i" <<<"$USED"; then NEXT="$i"; break; fi
done
[[ -n "$NEXT" ]] || die "No free addresses left in ${WG_SUBNET}."
CLIENT_IP="${BASE}.${NEXT}"

# --- keys ------------------------------------------------------------
umask 077
CLIENT_PRIV="$(wg genkey)"
CLIENT_PUB="$(wg pubkey <<<"$CLIENT_PRIV")"
CLIENT_PSK="$(wg genpsk)"       # extra pre-shared-key layer, per peer

# --- what the client is allowed to route -----------------------------
if [[ "$MODE" == full ]]; then
  ALLOWED="0.0.0.0/0, ::/0"     # everything -> privacy
else
  ALLOWED="${WG_SUBNET}, ${HOME_LAN}"   # only VPN + home LAN
fi

# --- write the client config -----------------------------------------
cat > "$CLIENT_CONF" <<EOF
# ${NAME}  (${MODE}-tunnel)  — generated $(date -u +%FT%TZ)
[Interface]
PrivateKey = ${CLIENT_PRIV}
Address    = ${CLIENT_IP}/32
DNS        = ${CLIENT_DNS}

[Peer]
PublicKey           = ${SERVER_PUB}
PresharedKey        = ${CLIENT_PSK}
Endpoint            = ${ENDPOINT}
AllowedIPs          = ${ALLOWED}
PersistentKeepalive = 25
EOF
chmod 600 "$CLIENT_CONF"

# --- append the peer to the hub, and load it live --------------------
cat >> "$CONF" <<EOF

[Peer]
# ${NAME} (${MODE})
PublicKey    = ${CLIENT_PUB}
PresharedKey = ${CLIENT_PSK}
AllowedIPs   = ${CLIENT_IP}/32
EOF

wg syncconf "$WG_IF" <(wg-quick strip "$WG_IF")

# --- output ----------------------------------------------------------
echo
msg "Added '${NAME}'  ->  ${CLIENT_IP}  (${MODE}-tunnel, endpoint ${ENDPOINT})"
echo
echo "Config file (for Windows/Linux — import this):"
echo "    ${CLIENT_CONF}"
echo
echo "Scan this with the WireGuard app on your phone/tablet:"
echo "--------------------------------------------------------------------"
qrencode -t ansiutf8 < "$CLIENT_CONF"
echo "--------------------------------------------------------------------"
echo
echo "To copy the raw config to your PC from your own machine:"
echo "    pct pull <CTID> ${CLIENT_CONF} ${NAME}.conf     # from Proxmox host"
echo "    # or:  cat ${CLIENT_CONF}"
