#!/usr/bin/env bash
#
# backup.sh — save or restore the hub's keys + config
# ------------------------------------------------------------------
# RUN INSIDE THE HUB CONTAINER, as root.
#
#   ./backup.sh                 -> writes wg-hub-backup-<date>.tar.gz here
#   ./backup.sh /path/dir       -> writes the archive into that directory
#   ./backup.sh restore <file>  -> restores /etc/wireguard from an archive
#
# The archive contains PRIVATE KEYS. Treat it like a password: keep it
# somewhere safe, off the box. After restoring, run: systemctl restart
# wg-quick@wg0

set -euo pipefail
msg() { echo -e "\033[1;32m[+]\033[0m $*"; }
die() { echo -e "\033[1;31m[x]\033[0m $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "Run as root."

if [[ "${1:-}" == "restore" ]]; then
  SRC="${2:-}"
  [[ -f "$SRC" ]] || die "Usage: $0 restore <archive.tar.gz>"
  msg "Restoring /etc/wireguard from $SRC ..."
  [[ -d /etc/wireguard ]] && cp -a /etc/wireguard "/etc/wireguard.pre-restore.$(date +%s)"
  tar xzf "$SRC" -C /
  msg "Done. Now: systemctl restart wg-quick@\${WG_IF:-wg0}"
  exit 0
fi

DEST_DIR="${1:-$PWD}"
[[ -d "$DEST_DIR" ]] || die "Not a directory: $DEST_DIR"
OUT="${DEST_DIR%/}/wg-hub-backup-$(hostname)-$(date +%Y%m%d-%H%M%S).tar.gz"

umask 077
msg "Backing up /etc/wireguard ..."
tar czf "$OUT" -C / etc/wireguard
chmod 600 "$OUT"
msg "Wrote $OUT"
echo "    Contains private keys — move it somewhere safe and off this box."
echo "    Restore later with:  ./backup.sh restore $OUT"
