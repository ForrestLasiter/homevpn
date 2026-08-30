#!/usr/bin/env bash
#
# status.sh — one-glance health of the hub
# ------------------------------------------------------------------
# RUN INSIDE THE HUB CONTAINER. Read-only; safe to run anytime.

set -uo pipefail
[[ -f /etc/wireguard/hub.env ]] && { set -a; . /etc/wireguard/hub.env; set +a; }
WG_IF="${WG_IF:-wg0}"

ok()   { echo -e "  \033[1;32m✓\033[0m $*"; }
bad()  { echo -e "  \033[1;31m✗\033[0m $*"; }
info() { echo -e "  \033[1;34m•\033[0m $*"; }

echo "=== Home VPN hub status ==="

# tunnel up?
if systemctl is-active --quiet "wg-quick@${WG_IF}"; then ok "tunnel wg-quick@${WG_IF} is active"
else bad "tunnel wg-quick@${WG_IF} is NOT active  (systemctl start wg-quick@${WG_IF})"; fi

# IP forwarding
if [[ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" == 1 ]]; then ok "IPv4 forwarding on"
else bad "IPv4 forwarding OFF — clients won't reach the internet/LAN"; fi

# peers + who's online
if command -v wg >/dev/null && wg show "$WG_IF" >/dev/null 2>&1; then
  peers=$(wg show "$WG_IF" peers | grep -c . || true)
  now=$(date +%s); online=0
  while IFS=$'\t' read -r _pk _psk _ep _aip hs _r _t _k; do
    [[ -n "$hs" && "$hs" != 0 && $(( now - hs )) -lt 180 ]] && online=$((online+1))
  done < <(wg show "$WG_IF" dump | tail -n +2)
  info "peers enrolled: ${peers}   online now: ${online}"
else
  info "no live interface to query yet"
fi

# listening port
if command -v ss >/dev/null && ss -lun 2>/dev/null | grep -q ":${WG_PORT:-51820} "; then
  ok "listening on UDP ${WG_PORT:-51820}"
else info "UDP ${WG_PORT:-51820} not seen listening (ss unavailable or tunnel down)"; fi

# DuckDNS: does the name resolve, and to our current public IP?
if [[ -n "${DUCKDNS_DOMAIN:-}" ]]; then
  pub="$(curl -s --max-time 5 https://api.ipify.org || true)"
  res="$(getent hosts "${DUCKDNS_DOMAIN}.duckdns.org" | awk '{print $1; exit}')"
  if [[ -n "$pub" && "$pub" == "$res" ]]; then ok "DuckDNS ${DUCKDNS_DOMAIN}.duckdns.org -> ${res} (matches public IP)"
  elif [[ -n "$res" ]]; then bad "DuckDNS resolves to ${res} but public IP is ${pub:-unknown} — updater may be behind"
  else bad "DuckDNS ${DUCKDNS_DOMAIN}.duckdns.org does not resolve yet"; fi
else
  info "DuckDNS not configured"
fi

# Pi-hole
if command -v pihole >/dev/null 2>&1; then
  if pihole status 2>/dev/null | grep -qi 'enabled'; then ok "Pi-hole is up (ad blocking on)"
  else info "Pi-hole installed but not reporting enabled"; fi
else
  info "Pi-hole not installed (run ./pihole-setup.sh for network-wide ad blocking)"
fi

echo "=========================="
