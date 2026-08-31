#!/usr/bin/env bash
#
# encrypt-dns.sh — encrypt the hub's upstream DNS (DoT via unbound)
# ------------------------------------------------------------------
# RUN INSIDE THE HUB CONTAINER, as root, AFTER pihole-setup.sh. Idempotent.
#
# By default Pi-hole forwards your DNS lookups to 1.1.1.1/9.9.9.9 in PLAINTEXT,
# so your ISP can still see every domain you resolve. This installs unbound as
# a local DNS-over-TLS forwarder (127.0.0.1:5053) and points Pi-hole at it, so
# upstream DNS is encrypted. unbound also validates DNSSEC (Pi-hole's own
# DNSSEC is turned off to avoid doing it twice).
#
#   Result chain:  client -> Pi-hole (block) -> unbound (DNSSEC) -> DoT -> resolver

set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
msg()  { echo -e "\033[1;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
die()  { echo -e "\033[1;31m[x]\033[0m $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Run as root."

msg "Installing unbound..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq unbound ca-certificates

msg "Configuring unbound as a DNS-over-TLS forwarder on 127.0.0.1:5053..."
cat > /etc/unbound/unbound.conf.d/pihole-doT.conf <<'EOF'
server:
    verbosity: 0
    interface: 127.0.0.1@5053
    access-control: 127.0.0.0/8 allow
    do-ip6: no
    hide-identity: yes
    hide-version: yes
    tls-cert-bundle: "/etc/ssl/certs/ca-certificates.crt"
    cache-min-ttl: 60
    cache-max-ttl: 86400
forward-zone:
    name: "."
    forward-tls-upstream: yes
    forward-addr: 1.1.1.1@853#cloudflare-dns.com
    forward-addr: 1.0.0.1@853#cloudflare-dns.com
    forward-addr: 9.9.9.9@853#dns.quad9.net
EOF
systemctl enable unbound >/dev/null 2>&1 || true
systemctl restart unbound
sleep 3

# sanity check unbound before we hand DNS to it
dig +short @127.0.0.1 -p 5053 example.com >/dev/null 2>&1 \
  || die "unbound is not resolving on 127.0.0.1:5053 — leaving Pi-hole upstream unchanged."
msg "unbound is resolving over encrypted DoT."

if command -v pihole-FTL >/dev/null; then
  msg "Pointing Pi-hole upstream at unbound and disabling Pi-hole's own DNSSEC..."
  pihole-FTL --config dns.upstreams '["127.0.0.1#5053"]'
  pihole-FTL --config dns.dnssec false
  # make Pi-hole start after unbound (NOT after wg-quick — that closes a
  # systemd ordering cycle via nss-lookup.target and breaks wg0 at boot).
  mkdir -p /etc/systemd/system/pihole-FTL.service.d
  cat > /etc/systemd/system/pihole-FTL.service.d/override.conf <<EOF
[Unit]
After=unbound.service
Wants=unbound.service
EOF
  systemctl daemon-reload
  systemctl restart pihole-FTL
  sleep 2
  msg "Done. Verify:"
  echo "    dig +short @10.10.10.1 example.com        # resolves"
  echo "    dig @10.10.10.1 dnssec-failed.org         # SERVFAIL (DNSSEC works)"
else
  warn "Pi-hole not found. unbound is up on 127.0.0.1#5053 — point your resolver there."
fi
