#!/usr/bin/env bash
#
# harden.sh — optional extra hardening for the hub
# ------------------------------------------------------------------
# RUN INSIDE THE HUB CONTAINER, as root. Idempotent — safe to re-run.
#
# Does two low-risk, high-value things:
#   1. turns on automatic security updates (the hub is internet-facing)
#   2. if Pi-hole is installed: adds two curated, low-false-positive
#      blocklists (OISD Big + Hagezi Pro) and enables DNSSEC, then
#      rebuilds gravity. Skips this part cleanly if Pi-hole isn't there.

set -euo pipefail
# Pi-hole lives in /usr/local/bin — keep it on PATH under bare shells.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

msg()  { echo -e "\033[1;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
die()  { echo -e "\033[1;31m[x]\033[0m $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Run as root."

# --- 1. automatic security updates ----------------------------------
msg "Enabling automatic security updates..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq unattended-upgrades >/dev/null
cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable --now unattended-upgrades >/dev/null 2>&1 || true

# --- 2. Pi-hole extras (only if Pi-hole is installed) ---------------
if command -v pihole >/dev/null && [[ -f /etc/pihole/gravity.db ]]; then
  DB=/etc/pihole/gravity.db
  msg "Adding curated blocklists (OISD Big + Hagezi Pro)..."
  pihole-FTL sqlite3 "$DB" <<'SQL'
INSERT OR IGNORE INTO adlist (address,enabled,comment) VALUES ('https://big.oisd.nl',1,'OISD Big');
INSERT OR IGNORE INTO adlist (address,enabled,comment) VALUES ('https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/pro.txt',1,'Hagezi Pro');
SQL
  msg "Enabling DNSSEC..."
  pihole-FTL --config dns.dnssec true >/dev/null 2>&1 || warn "Couldn't set DNSSEC (older Pi-hole?)."
  msg "Rebuilding gravity (downloads the new lists — takes a moment)..."
  pihole -g
  echo -n "    Blocked domains now: "
  pihole-FTL sqlite3 "$DB" "SELECT COUNT(*) FROM gravity;"
else
  warn "Pi-hole not installed — skipping blocklists/DNSSEC (run ./pihole-setup.sh first)."
fi

echo
msg "Hardening done."
