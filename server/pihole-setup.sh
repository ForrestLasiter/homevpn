#!/usr/bin/env bash
#
# pihole-setup.sh — network-wide ad/tracker blocking on the hub
# ------------------------------------------------------------------
# RUN INSIDE THE HUB CONTAINER, as root, AFTER bootstrap.sh.
#
# Installs Pi-hole unattended and binds it to the VPN interface, so
# every device on the VPN gets ad + tracker blocking via DNS. Then it
# flips the DNS the hub hands out to point at itself (10.10.10.1).
#
# After this runs, re-issue client configs (they'll pick up the new DNS)
# OR just edit the DNS line of existing clients to the hub address.

set -euo pipefail

# --- load shared config if present (for PIHOLE_PASSWORD, upstreams) ---
for _cfg in "${CONFIG_FILE:-}" "$(dirname "${BASH_SOURCE[0]}")/config.env" \
            "/opt/wg-hub/config.env" "/etc/wireguard/config.env"; do
  [[ -n "${_cfg:-}" && -f "$_cfg" ]] && { set -a; . "$_cfg"; set +a; break; }
done

msg()  { echo -e "\033[1;32m[+]\033[0m $*"; }
die()  { echo -e "\033[1;31m[x]\033[0m $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Run as root."
[[ -f /etc/wireguard/hub.env ]] || die "Run bootstrap.sh first."
# shellcheck disable=SC1091
source /etc/wireguard/hub.env

PIHOLE_PASSWORD="${PIHOLE_PASSWORD:-changeme-admin}"   # web UI password
UPSTREAM_DNS_1="${UPSTREAM_DNS_1:-1.1.1.1}"
UPSTREAM_DNS_2="${UPSTREAM_DNS_2:-9.9.9.9}"

# Pre-seed answers so the installer runs with no prompts.
install -d /etc/pihole
cat > /etc/pihole/setupVars.conf <<EOF
PIHOLE_INTERFACE=${WG_IF}
IPV4_ADDRESS=${WG_ADDR}/${WG_CIDR}
IPV6_ADDRESS=
PIHOLE_DNS_1=${UPSTREAM_DNS_1}
PIHOLE_DNS_2=${UPSTREAM_DNS_2}
QUERY_LOGGING=true
INSTALL_WEB_SERVER=true
INSTALL_WEB_INTERFACE=true
LIGHTTPD_ENABLED=true
CACHE_SIZE=10000
DNS_FQDN_REQUIRED=true
DNS_BOGUS_PRIV=true
DNSMASQ_LISTENING=single
BLOCKING_ENABLED=true
EOF

msg "Installing Pi-hole (unattended)..."
curl -fsSL https://install.pi-hole.net | bash /dev/stdin --unattended

msg "Setting the web-UI password..."
pihole -a -p "$PIHOLE_PASSWORD" || pihole setpassword "$PIHOLE_PASSWORD" || true

# Only answer DNS on the VPN interface — never expose the resolver to the
# internet (open resolvers get abused).
if command -v pihole >/dev/null; then
  pihole -a -i single >/dev/null 2>&1 || true
fi

# Point the hub's client DNS at itself for future add-client runs.
sed -i "s/^CLIENT_DNS=.*/CLIENT_DNS=${WG_ADDR}/" /etc/wireguard/hub.env

echo
msg "Pi-hole is up."
echo "    Admin UI:  http://${WG_ADDR}/admin   (reachable once you're on the VPN)"
echo "    Password:  ${PIHOLE_PASSWORD}   (change PIHOLE_PASSWORD and re-run to rotate)"
echo
msg "New clients will get DNS=${WG_ADDR} automatically."
echo "    For devices already enrolled, change their config's  DNS = ...  line to ${WG_ADDR}."
