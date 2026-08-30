#!/usr/bin/env bash
#
# uninstall.sh — tear the hub back down
# ------------------------------------------------------------------
# RUN INSIDE THE HUB CONTAINER, as root. Stops and disables the tunnel
# and the DuckDNS timer. By default it KEEPS /etc/wireguard (your keys);
# pass --purge to delete keys and configs too.
#
#   ./uninstall.sh            # stop services, keep keys/config
#   ./uninstall.sh --purge    # also delete /etc/wireguard (irreversible)
#
# Note: this does NOT uninstall Pi-hole (use `pihole uninstall`) and does
# NOT destroy the container (do that from the Proxmox host: pct destroy).

set -euo pipefail
msg()  { echo -e "\033[1;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
die()  { echo -e "\033[1;31m[x]\033[0m $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Run as root."
WG_IF="wg0"; [[ -f /etc/wireguard/hub.env ]] && { set -a; . /etc/wireguard/hub.env; set +a; }

msg "Stopping wg-quick@${WG_IF} ..."
systemctl disable --now "wg-quick@${WG_IF}" 2>/dev/null || true

msg "Stopping DuckDNS timer ..."
systemctl disable --now duckdns.timer 2>/dev/null || true
rm -f /etc/systemd/system/duckdns.service /etc/systemd/system/duckdns.timer
systemctl daemon-reload 2>/dev/null || true
rm -f /usr/local/bin/duckdns-update.sh /etc/duckdns.env
rm -f /etc/sysctl.d/99-wireguard-forward.conf && sysctl -q --system 2>/dev/null || true

if [[ "${1:-}" == "--purge" ]]; then
  warn "Purging /etc/wireguard (keys + all client configs) ..."
  rm -rf /etc/wireguard
  msg "Purged. The hub is fully removed."
else
  msg "Services stopped. Kept /etc/wireguard (keys + configs)."
  echo "    Re-run ./bootstrap.sh to bring it back, or ./uninstall.sh --purge to wipe."
fi
