#!/usr/bin/env bash
#
# remove-client.sh — revoke a device
# ------------------------------------------------------------------
# RUN INSIDE THE HUB CONTAINER, as root.   ./remove-client.sh <name>
# Drops the peer from wg0.conf, reloads the live tunnel (so the device
# is cut off immediately), and deletes its stored config.

set -euo pipefail
msg() { echo -e "\033[1;32m[+]\033[0m $*"; }
die() { echo -e "\033[1;31m[x]\033[0m $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Run as root."
[[ -f /etc/wireguard/hub.env ]] || die "Run bootstrap.sh first."
# shellcheck disable=SC1091
source /etc/wireguard/hub.env
CONF="/etc/wireguard/${WG_IF}.conf"

NAME="${1:-}"
[[ -n "$NAME" ]] || die "Usage: $0 <name>   (see ./list-clients.sh for names)"
grep -qE "^[[:space:]]*#[[:space:]]*${NAME}[[:space:]]" "$CONF" \
  || die "No peer named '$NAME' in $CONF. Try: ./list-clients.sh"

# back up before we touch it
cp -a "$CONF" "${CONF}.bak.$(date +%s)"

# rewrite the config without the target peer's [Peer] block
TMP="$(mktemp)"
awk -v target="$NAME" '
function flush(){ if(buf!=""){ if(!drop) printf "%s", buf } buf=""; drop=0 }
/^\[Peer\]/      { flush(); buf=$0 ORS; inpeer=1; next }
/^\[Interface\]/ { flush(); inpeer=0; print; next }
{
  if(inpeer){
    buf = buf $0 ORS
    if($0 ~ /^[[:space:]]*#/){
      l=$0; sub(/^[[:space:]]*#[[:space:]]*/,"",l); sub(/[[:space:]].*/,"",l)
      if(l==target) drop=1
    }
  } else print
}
END{ flush() }
' "$CONF" > "$TMP"
mv "$TMP" "$CONF"
chmod 600 "$CONF"

# reload the live tunnel so the revoke takes effect now
if systemctl is-active --quiet "wg-quick@${WG_IF}"; then
  wg syncconf "$WG_IF" <(wg-quick strip "$WG_IF")
fi

# remove the stored client config
rm -f "/etc/wireguard/clients/${NAME}.conf"

msg "Removed '${NAME}'. It can no longer connect."
echo "    (a timestamped backup of the old config is in /etc/wireguard/)"
