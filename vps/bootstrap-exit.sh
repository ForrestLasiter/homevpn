#!/usr/bin/env bash
#
# bootstrap-exit.sh — turn a fresh VPS into a WireGuard EXIT node
# ------------------------------------------------------------------
# RUN THIS ON THE VPS (a cheap always-on cloud box: Hetzner, DO, Vultr),
# Debian/Ubuntu, as root. It's the twin of the home bootstrap, minus
# DuckDNS/Pi-hole — a VPS has a static public IP, so devices dial it
# directly and exit to the internet from HERE (a not-your-house IP).
#
#   READ FIRST: docs/PHASE2-vps-exit.md — this is pseudonymity, not
#   anonymity. The IP traces to whoever rented the box.
#
# After this, enroll devices with ./add-exit-client.sh <name>.

set -euo pipefail

# --- load shared config if present (config.env overrides these) ------
for _cfg in "${CONFIG_FILE:-}" "$(dirname "${BASH_SOURCE[0]}")/config.env" \
            "$(dirname "${BASH_SOURCE[0]}")/../config.env" "/opt/wg-exit/config.env"; do
  # shellcheck source=/dev/null
  [[ -n "${_cfg:-}" && -f "$_cfg" ]] && { set -a; . "$_cfg"; set +a; break; }
done

EXIT_IF="${EXIT_IF:-wg0}"
EXIT_PORT="${VPS_WG_PORT:-51820}"
EXIT_ADDR="${VPS_WG_ADDR:-10.20.0.1}"
EXIT_CIDR="${VPS_WG_CIDR:-24}"
EXIT_SUBNET="${EXIT_ADDR%.*}.0/${EXIT_CIDR}"

msg()  { echo -e "\033[1;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
die()  { echo -e "\033[1;31m[x]\033[0m $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Run as root."

msg "Installing packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq wireguard wireguard-tools iptables qrencode curl >/dev/null

msg "Enabling IP forwarding..."
cat > /etc/sysctl.d/99-wg-exit.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
# Apply the two keys directly; `sysctl --system` fails in an unprivileged
# LXC (tries to set host-only keys). The drop-in handles reboot persistence.
sysctl -q -w net.ipv4.ip_forward=1 2>/dev/null || true
sysctl -q -w net.ipv6.conf.all.forwarding=1 2>/dev/null || true

KEYDIR="/etc/wireguard/keys"; install -d -m 700 "$KEYDIR"
if [[ ! -f "$KEYDIR/exit.key" ]]; then
  msg "Generating exit keypair..."
  umask 077; wg genkey | tee "$KEYDIR/exit.key" | wg pubkey > "$KEYDIR/exit.pub"
fi
EXIT_PRIV="$(cat "$KEYDIR/exit.key")"; EXIT_PUB="$(cat "$KEYDIR/exit.pub")"

WAN_IF="$(ip -4 route show default | awk '{print $5; exit}')"
[[ -n "$WAN_IF" ]] || die "Could not detect the default interface."
PUBIP="$(curl -s --max-time 5 https://api.ipify.org || true)"
msg "Outbound interface: $WAN_IF   Public IP: ${PUBIP:-unknown}"

CONF="/etc/wireguard/${EXIT_IF}.conf"
PEERS=""
if [[ -f "$CONF" ]] && grep -q '^\[Peer\]' "$CONF"; then
  PEERS="$(awk '/^\[Peer\]/{p=1} p{print}' "$CONF")"
fi

umask 077
cat > "$CONF" <<EOF
# Managed by bootstrap-exit.sh — [Interface] regenerated each run,
# [Peer] blocks preserved. Add peers with ./add-exit-client.sh
[Interface]
Address    = ${EXIT_ADDR}/${EXIT_CIDR}
ListenPort = ${EXIT_PORT}
PrivateKey = ${EXIT_PRIV}

PostUp   = iptables -t nat -A POSTROUTING -s ${EXIT_SUBNET} -o ${WAN_IF} -j MASQUERADE
PostUp   = iptables -A FORWARD -i ${EXIT_IF} -j ACCEPT
PostUp   = iptables -A FORWARD -o ${EXIT_IF} -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s ${EXIT_SUBNET} -o ${WAN_IF} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${EXIT_IF} -j ACCEPT
PostDown = iptables -D FORWARD -o ${EXIT_IF} -j ACCEPT
EOF
[[ -n "$PEERS" ]] && printf '\n%s\n' "$PEERS" >> "$CONF"

cat > /etc/wireguard/exit.env <<EOF
EXIT_IF=${EXIT_IF}
EXIT_PORT=${EXIT_PORT}
EXIT_ADDR=${EXIT_ADDR}
EXIT_CIDR=${EXIT_CIDR}
EXIT_SUBNET=${EXIT_SUBNET}
EXIT_PUB=${EXIT_PUB}
EXIT_ENDPOINT=${EXIT_ENDPOINT:-${PUBIP}}
CLIENT_DNS=${CLIENT_DNS:-1.1.1.1}
EOF

systemctl enable "wg-quick@${EXIT_IF}" >/dev/null 2>&1 || true
if systemctl is-active --quiet "wg-quick@${EXIT_IF}"; then
  wg syncconf "$EXIT_IF" <(wg-quick strip "$EXIT_IF")
else
  systemctl restart "wg-quick@${EXIT_IF}"
fi

echo
msg "Exit node up. Public key:"
echo "    $EXIT_PUB"
echo "    Endpoint devices will use: ${EXIT_ENDPOINT:-${PUBIP}}:${EXIT_PORT}"
warn "Open UDP ${EXIT_PORT} in your VPS provider's firewall/security group."
echo
msg "Next: enroll a device  ->  ./add-exit-client.sh laptop"
