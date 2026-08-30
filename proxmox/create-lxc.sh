#!/usr/bin/env bash
#
# create-lxc.sh — create the WireGuard hub container on Proxmox
# ------------------------------------------------------------------
# RUN THIS ON THE PROXMOX HOST (not inside a container), as root.
#
# It creates a small Debian 12 LXC, gives it the TUN device that
# WireGuard needs, starts it, and pushes the server/ scripts inside.
#
# Everything is driven by the variables below — edit them, then run.
# Re-running with an existing CTID is refused so you can't clobber a
# container by accident.

set -euo pipefail

# ---- settings you may want to change --------------------------------
CTID="${CTID:-910}"                 # container ID (must be unused)
HOSTNAME="${HOSTNAME:-wg-hub}"
STORAGE="${STORAGE:-local-lvm}"     # where the rootfs lives
BRIDGE="${BRIDGE:-vmbr0}"           # your LAN bridge
DISK_GB="${DISK_GB:-4}"
RAM_MB="${RAM_MB:-512}"
CORES="${CORES:-1}"
TEMPLATE_STORE="${TEMPLATE_STORE:-local}"
TEMPLATE="${TEMPLATE:-debian-12-standard}"   # matched by name below
# Give the container a fixed LAN IP so your router port-forward always
# lands in the right place. Use dhcp only if you also set a DHCP reservation.
NET_IP="${NET_IP:-dhcp}"            # e.g. 192.168.1.10/24  (or dhcp)
NET_GW="${NET_GW:-}"               # e.g. 192.168.1.1       (blank for dhcp)
UNPRIVILEGED="${UNPRIVILEGED:-1}"   # 1 = unprivileged (recommended)
# ---------------------------------------------------------------------

msg() { echo -e "\033[1;32m[+]\033[0m $*"; }
die() { echo -e "\033[1;31m[!]\033[0m $*" >&2; exit 1; }

command -v pct >/dev/null || die "pct not found — run this on the Proxmox host."
pct status "$CTID" &>/dev/null && die "CTID $CTID already exists. Pick another CTID."

# --- find/download the Debian 12 template ---------------------------
msg "Locating $TEMPLATE template on '$TEMPLATE_STORE'..."
TMPL_PATH="$(pveam list "$TEMPLATE_STORE" 2>/dev/null | awk -v t="$TEMPLATE" '$1 ~ t {print $1}' | head -n1 || true)"
if [[ -z "${TMPL_PATH:-}" ]]; then
  msg "Not present — downloading..."
  pveam update
  AVAIL="$(pveam available --section system | awk -v t="$TEMPLATE" '$2 ~ t {print $2}' | sort | tail -n1)"
  [[ -n "$AVAIL" ]] || die "Could not find a $TEMPLATE template via pveam available."
  pveam download "$TEMPLATE_STORE" "$AVAIL"
  TMPL_PATH="$TEMPLATE_STORE:vztmpl/$AVAIL"
fi
msg "Template: $TMPL_PATH"

# --- network argument ------------------------------------------------
if [[ "$NET_IP" == "dhcp" ]]; then
  NETCONF="name=eth0,bridge=${BRIDGE},ip=dhcp"
else
  [[ -n "$NET_GW" ]] || die "NET_GW must be set when NET_IP is a static address."
  NETCONF="name=eth0,bridge=${BRIDGE},ip=${NET_IP},gw=${NET_GW}"
fi

msg "Creating CT $CTID ($HOSTNAME)..."
pct create "$CTID" "$TMPL_PATH" \
  --hostname "$HOSTNAME" \
  --cores "$CORES" \
  --memory "$RAM_MB" \
  --swap 256 \
  --rootfs "${STORAGE}:${DISK_GB}" \
  --net0 "$NETCONF" \
  --features "nesting=1" \
  --unprivileged "$UNPRIVILEGED" \
  --onboot 1 \
  --start 0

# --- give the container /dev/net/tun (WireGuard needs it) ------------
CONF="/etc/pve/lxc/${CTID}.conf"
msg "Granting TUN device to CT $CTID..."
if ! grep -q "net/tun" "$CONF"; then
  cat >> "$CONF" <<'EOF'
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
EOF
fi

msg "Ensuring the wireguard module is loaded on the host..."
modprobe wireguard 2>/dev/null || true
grep -qx wireguard /etc/modules 2>/dev/null || echo wireguard >> /etc/modules

msg "Starting CT $CTID..."
pct start "$CTID"
sleep 5

# --- push the server scripts into the container ----------------------
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../server" && pwd)"
msg "Copying server scripts into the container at /opt/wg-hub ..."
pct exec "$CTID" -- mkdir -p /opt/wg-hub
for f in "$SRC_DIR"/*.sh; do
  pct push "$CTID" "$f" "/opt/wg-hub/$(basename "$f")"
  pct exec "$CTID" -- chmod +x "/opt/wg-hub/$(basename "$f")"
done

echo
msg "Container $CTID is up."
echo    "    Next:  enter it and run the bootstrap:"
echo    "      pct enter $CTID"
echo    "      cd /opt/wg-hub && ./bootstrap.sh"
echo
echo    "    (Edit the variables at the top of bootstrap.sh first —"
echo    "     especially your DuckDNS domain + token.)"
