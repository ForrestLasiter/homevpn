#!/usr/bin/env bash
#
# bootstrap.sh — turn a fresh Debian box into the WireGuard hub
# ------------------------------------------------------------------
# RUN THIS INSIDE THE CONTAINER (or on any Debian/Ubuntu machine you
# want to be the hub), as root. It is idempotent: safe to run again.
#
# What it does:
#   1. installs wireguard + tools
#   2. turns on IP forwarding (so clients can reach the internet + LAN)
#   3. generates the hub's keypair (once)
#   4. writes /etc/wireguard/wg0.conf with NAT so traffic can exit
#   5. enables + starts the tunnel on boot
#   6. installs the DuckDNS updater (so clients always find you)
#
# Adding client devices is a SEPARATE step: ./add-client.sh <name>

set -euo pipefail

# --- load shared config if present (config.env overrides these defaults) ---
for _cfg in "${CONFIG_FILE:-}" "$(dirname "${BASH_SOURCE[0]}")/config.env" \
            "/opt/wg-hub/config.env" "/etc/wireguard/config.env"; do
  [[ -n "${_cfg:-}" && -f "$_cfg" ]] && { set -a; . "$_cfg"; set +a; break; }
done

# ==== SETTINGS — edit these (or set them in config.env) ==============
WG_IF="${WG_IF:-wg0}"
WG_PORT="${WG_PORT:-51820}"           # UDP port to forward on your router
WG_ADDR="${WG_ADDR:-10.10.10.1}"      # the hub's address inside the VPN
WG_CIDR="${WG_CIDR:-24}"              # => VPN subnet 10.10.10.0/24
WG_SUBNET="${WG_ADDR%.*}.0/${WG_CIDR}"

# Your home LAN, so split-tunnel clients can reach home devices.
# Find it with:  ip route | grep -v wg | grep /  (looks like 192.168.1.0/24)
HOME_LAN="${HOME_LAN:-192.168.1.0/24}"

# DNS handed to clients. Point at the hub (10.10.10.1) once you install
# Pi-hole (./pihole-setup.sh) for network-wide ad blocking. Until then,
# a public resolver keeps things working.
CLIENT_DNS="${CLIENT_DNS:-1.1.1.1}"

# DuckDNS — so your changing home IP always resolves to a stable name.
# Make a domain at https://www.duckdns.org and paste them here.
DUCKDNS_DOMAIN="${DUCKDNS_DOMAIN:-}"  # e.g. forresthome  (no .duckdns.org)
DUCKDNS_TOKEN="${DUCKDNS_TOKEN:-}"    # the token shown on duckdns.org
# =====================================================================

msg()  { echo -e "\033[1;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
die()  { echo -e "\033[1;31m[x]\033[0m $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root."

# --- 1. packages -----------------------------------------------------
msg "Installing packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq wireguard wireguard-tools iptables qrencode curl >/dev/null

# --- 2. IP forwarding ------------------------------------------------
msg "Enabling IP forwarding..."
cat > /etc/sysctl.d/99-wireguard-forward.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl -q --system

# --- 3. hub keypair --------------------------------------------------
KEYDIR="/etc/wireguard/keys"
install -d -m 700 "$KEYDIR"
if [[ ! -f "$KEYDIR/server.key" ]]; then
  msg "Generating hub keypair..."
  umask 077
  wg genkey | tee "$KEYDIR/server.key" | wg pubkey > "$KEYDIR/server.pub"
else
  msg "Hub keypair already exists — keeping it."
fi
SERVER_PRIV="$(cat "$KEYDIR/server.key")"
SERVER_PUB="$(cat "$KEYDIR/server.pub")"

# --- detect the outbound interface for NAT ---------------------------
WAN_IF="$(ip -4 route show default | awk '{print $5; exit}')"
[[ -n "$WAN_IF" ]] || die "Could not detect the default network interface."
msg "Outbound interface: $WAN_IF"

# --- 4. wg0.conf -----------------------------------------------------
# Preserve any [Peer] blocks already added by add-client.sh.
CONF="/etc/wireguard/${WG_IF}.conf"
PEERS=""
if [[ -f "$CONF" ]] && grep -q '^\[Peer\]' "$CONF"; then
  msg "Preserving existing peers from $CONF ..."
  PEERS="$(awk '/^\[Peer\]/{p=1} p{print}' "$CONF")"
fi

msg "Writing $CONF ..."
umask 077
cat > "$CONF" <<EOF
# Managed by bootstrap.sh — the [Interface] block is regenerated on each
# run; [Peer] blocks below are preserved. Add peers with ./add-client.sh
[Interface]
Address    = ${WG_ADDR}/${WG_CIDR}
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIV}

# NAT: let VPN clients reach the internet and the home LAN through this hub
PostUp   = iptables -t nat -A POSTROUTING -s ${WG_SUBNET} -o ${WAN_IF} -j MASQUERADE
PostUp   = iptables -A FORWARD -i ${WG_IF} -j ACCEPT
PostUp   = iptables -A FORWARD -o ${WG_IF} -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s ${WG_SUBNET} -o ${WAN_IF} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_IF} -j ACCEPT
PostDown = iptables -D FORWARD -o ${WG_IF} -j ACCEPT
EOF

if [[ -n "$PEERS" ]]; then
  printf '\n%s\n' "$PEERS" >> "$CONF"
fi

# stash values add-client.sh needs, so it stays in sync with this run
cat > /etc/wireguard/hub.env <<EOF
WG_IF=${WG_IF}
WG_PORT=${WG_PORT}
WG_ADDR=${WG_ADDR}
WG_CIDR=${WG_CIDR}
WG_SUBNET=${WG_SUBNET}
HOME_LAN=${HOME_LAN}
CLIENT_DNS=${CLIENT_DNS}
DUCKDNS_DOMAIN=${DUCKDNS_DOMAIN}
SERVER_PUB=${SERVER_PUB}
EOF

# --- 5. enable + (re)start ------------------------------------------
msg "Enabling wg-quick@${WG_IF} on boot..."
systemctl enable "wg-quick@${WG_IF}" >/dev/null 2>&1 || true
if systemctl is-active --quiet "wg-quick@${WG_IF}"; then
  msg "Reloading tunnel with the new config..."
  wg syncconf "$WG_IF" <(wg-quick strip "$WG_IF")
else
  msg "Starting tunnel..."
  systemctl restart "wg-quick@${WG_IF}"
fi

# --- 6. DuckDNS updater ---------------------------------------------
if [[ -n "$DUCKDNS_DOMAIN" && -n "$DUCKDNS_TOKEN" ]]; then
  msg "Installing DuckDNS updater for ${DUCKDNS_DOMAIN}.duckdns.org ..."
  install -m 700 "$(dirname "$0")/duckdns-update.sh" /usr/local/bin/duckdns-update.sh
  cat > /etc/duckdns.env <<EOF
DUCKDNS_DOMAIN=${DUCKDNS_DOMAIN}
DUCKDNS_TOKEN=${DUCKDNS_TOKEN}
EOF
  chmod 600 /etc/duckdns.env
  cat > /etc/systemd/system/duckdns.service <<'EOF'
[Unit]
Description=Update DuckDNS with current public IP
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
EnvironmentFile=/etc/duckdns.env
ExecStart=/usr/local/bin/duckdns-update.sh
EOF
  cat > /etc/systemd/system/duckdns.timer <<'EOF'
[Unit]
Description=Refresh DuckDNS every 5 minutes
[Timer]
OnBootSec=30
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now duckdns.timer >/dev/null
  /usr/local/bin/duckdns-update.sh || warn "First DuckDNS update failed — check token/domain."
else
  warn "DuckDNS not configured (DUCKDNS_DOMAIN/TOKEN blank) — skipping."
  warn "Clients will need your raw public IP until you set this up."
fi

echo
msg "Hub is up. Public key:"
echo "    $SERVER_PUB"
wg show "$WG_IF" || true
echo
msg "Next: add a device  ->  ./add-client.sh phone"
[[ -n "$DUCKDNS_DOMAIN" ]] && echo "     Endpoint clients will use: ${DUCKDNS_DOMAIN}.duckdns.org:${WG_PORT}"
echo
warn "Don't forget the router port-forward:  UDP ${WG_PORT}  ->  this container.  (see docs/ROUTER.md)"
