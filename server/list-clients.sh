#!/usr/bin/env bash
#
# list-clients.sh — who's enrolled, and are they connected right now?
# ------------------------------------------------------------------
# RUN INSIDE THE HUB CONTAINER. Reads names/IPs from wg0.conf and joins
# them with live handshake data from `wg show`.

set -euo pipefail
die() { echo -e "\033[1;31m[x]\033[0m $*" >&2; exit 1; }
[[ -f /etc/wireguard/hub.env ]] || die "Run bootstrap.sh first."
# shellcheck disable=SC1091
source /etc/wireguard/hub.env
CONF="/etc/wireguard/${WG_IF}.conf"
[[ -f "$CONF" ]] || die "No $CONF found."

# pubkey -> last handshake (unix epoch) from the live interface
declare -A HS
if wg show "$WG_IF" >/dev/null 2>&1; then
  while IFS=$'\t' read -r pk _psk _ep _aip hs _rx _tx _ka; do
    [[ -n "$pk" ]] && HS["$pk"]="$hs"
  done < <(wg show "$WG_IF" dump | tail -n +2)
fi

now="$(date +%s)"
ago() {  # epoch -> "3m ago" / "never"
  local t="${1:-0}"
  [[ -z "$t" || "$t" == 0 ]] && { echo "never"; return; }
  local d=$(( now - t ))
  if   (( d < 60 ));   then echo "${d}s ago"
  elif (( d < 3600 )); then echo "$(( d/60 ))m ago"
  elif (( d < 86400 ));then echo "$(( d/3600 ))h ago"
  else echo "$(( d/86400 ))d ago"; fi
}

printf '%-18s %-16s %-16s %s\n' "NAME" "VPN IP" "LAST HANDSHAKE" "STATUS"
printf '%-18s %-16s %-16s %s\n' "----" "------" "--------------" "------"

# parse peers out of the config: name | pubkey | allowedip
awk '
function flush(){ if(pk!=""){printf "%s|%s|%s\n", name, pk, aip}; name="";pk="";aip="" }
/^\[Peer\]/       { flush(); next }
/^\[Interface\]/  { flush(); next }
/^[[:space:]]*#/  { if(name==""){ l=$0; sub(/^[[:space:]]*#[[:space:]]*/,"",l); name=l } next }
/^PublicKey/      { pk=$3; next }
/^AllowedIPs/     { aip=$3; next }
END { flush() }
' "$CONF" | while IFS='|' read -r name pk aip; do
  hs="${HS[$pk]:-0}"
  if [[ "$hs" != 0 && $(( now - hs )) -lt 180 ]]; then status="● online"; else status="○ offline"; fi
  printf '%-18s %-16s %-16s %s\n' "${name:-?}" "${aip%%/*}" "$(ago "$hs")" "$status"
done

echo
echo "(online = handshake within 3 min. Raw view: wg show ${WG_IF})"
