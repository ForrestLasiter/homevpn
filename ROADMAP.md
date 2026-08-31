# Roadmap — Home VPN

The wide view of where this project is going. Legend: ✅ done · 🚧 in progress ·
⬜ planned · 🧊 needs live infrastructure to finish/verify.

---

## Phase 1 — Home hub ✅
A WireGuard hub on your own Proxmox box. Privacy on untrusted Wi-Fi, your home
network from anywhere, a device mesh, and (optionally) network-wide ad blocking.

- ✅ `proxmox/create-lxc.sh` — one-command Debian 12 LXC with the TUN device
- ✅ `server/bootstrap.sh` — WireGuard + NAT + IP forwarding + DuckDNS updater
- ✅ `server/add-client.sh` — enroll a device, print a QR, full/split tunnel
- ✅ `server/pihole-setup.sh` — network-wide ad/tracker blocking
- ✅ `docs/ROUTER.md` — the one port-forward + CGNAT check

## Phase 1.5 — Public-ready polish ✅
Make it something *anyone* can clone and run, and something *we* can operate.

- ✅ `config.env` — one file for all settings; every script reads it
- ✅ `server/list-clients.sh` — who's enrolled + live handshake status
- ✅ `server/show-client.sh` — re-print a device's config / QR
- ✅ `server/remove-client.sh` — revoke a device cleanly
- ✅ `server/status.sh` — one-glance health (tunnel, peers, DNS, DuckDNS, IP fwd)
- ✅ `server/backup.sh` — back up / restore the hub's keys + config
- ✅ `server/uninstall.sh` — tear it all back down
- ✅ `server/harden.sh` — auto security updates + curated blocklists (OISD/Hagezi) + DNSSEC
- ✅ `server/encrypt-dns.sh` — encrypted upstream DNS (DoT via unbound), so the ISP can't see lookups
- ✅ Pi-hole listens in LOCAL (bind-dynamic) mode — survives wg0 coming up late after a reboot
- ✅ `LICENSE` (MIT), `CONTRIBUTING.md`, shellcheck CI (green), README polish

## Phase 2 — Cloud VPS exit node 🧊
Exit behind an IP that isn't your house. **Pseudonymity, not anonymity** — see
`docs/PHASE2-vps-exit.md` for the honest limits.

- ✅ `vps/bootstrap-exit.sh` — turn a fresh VPS into a WireGuard exit
- ✅ `vps/add-exit-client.sh` — full-tunnel device config that exits via the VPS
- 🧊 verify end-to-end (needs a rented VPS)
- ⬜ optional: home hub *chains* through the VPS (policy routing) so clients keep
      one config and the exit is chosen centrally

## Phase 3 — Tor 🧊
Real anonymity for the sessions that need it — kept separate on purpose.

- ✅ `docs/PHASE3-tor.md` — Tor Browser vs. a transparent-proxy peer, trade-offs
- 🧊 optional `tor` peer on the hub (needs testing)

## Cross-cutting / later
- ⬜ Generic Debian/Ubuntu host path (not just Proxmox) — bootstrap already works
      on any Debian box; document it.
- ⬜ IPv6 support end to end.
- ⬜ Flip repo **public** once Phase 1.5 lands and secrets hygiene is re-verified.

---

### How the pieces fit
```
        your devices (Win / Android / iOS / Linux)
                     │  WireGuard
                     ▼
        ┌─────────────────────────────┐        ┌────────────────────┐
        │  Home hub  (Proxmox LXC)     │  wg    │  VPS exit (Phase 2)│──▶ internet
        │  10.10.10.1                  │◀──────▶│  not-your-house IP │
        │  NAT · Pi-hole · home LAN    │        └────────────────────┘
        └─────────────────────────────┘
                     ▲
                     │  full-tunnel = privacy    split-tunnel = just home
```
