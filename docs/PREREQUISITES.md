# Prerequisites — everything you need, and where to get it

This project glues together a few free tools. Here's every external site and
piece of software involved, what it's for, what it costs, and how to get it.
Nothing here needs a credit card for Phase 1.

**Quick map:**

| Thing | Needed for | Cost | You install it, or the scripts do? |
|---|---|---|---|
| A server (Proxmox, or any Debian/Ubuntu box) | the hub | free (your hardware) | you |
| WireGuard client apps | each of your devices | free | you |
| DuckDNS account + token | reaching home as your IP changes | free | you (site) + scripts (updater) |
| Router with port-forwarding | letting the VPN in from outside | free (you own it) | you |
| `wireguard`, `qrencode`, `iptables` packages | the hub itself | free | **scripts** (apt) |
| Pi-hole *(optional)* | network-wide ad blocking | free | **script** (`pihole-setup.sh`) |
| A cloud VPS *(optional, Phase 2)* | a not-your-house exit IP | ~$4–6/mo | you |
| Tor Browser *(optional, Phase 3)* | true anonymity | free | you |

---

## Required for Phase 1 (the home hub)

### 1. A server to run the hub on
**What:** an always-on machine on your home network to be the VPN hub.
- **Proxmox VE** (recommended, what this repo automates): a free virtualization
  OS. The `proxmox/create-lxc.sh` script builds the container for you.
  Get it: **https://www.proxmox.com/en/downloads** (free; no account needed to
  download the ISO).
- **No Proxmox?** Any always-on **Debian 12 / Ubuntu** machine works too — a
  spare PC, a mini-PC, or a Raspberry Pi. Skip `create-lxc.sh` and run
  `server/bootstrap.sh` directly on that box.

### 2. WireGuard client apps (one per device)
**What:** the app your phone/PC uses to connect. Free and official from the
WireGuard project — **install the app from the source for your platform:**
- **Windows / macOS:** https://www.wireguard.com/install/
- **Android:** Google Play → search **"WireGuard"** (by *WireGuard Development
  Team*) — or https://play.google.com/store/apps/details?id=com.wireguard.android
- **iPhone / iPad:** App Store → search **"WireGuard"** (by *WireGuard
  Development Team*) — or https://apps.apple.com/app/wireguard/id1441195209
- **Linux:** your distro's package manager — `sudo apt install wireguard`
  (Debian/Ubuntu) or the equivalent. Docs: https://www.wireguard.com/install/

> ⚠️ Only install WireGuard from these official sources. Don't grab it from a
> random third-party download site.

### 3. DuckDNS — free dynamic DNS
**What:** your home's public IP changes over time; DuckDNS gives you a
permanent hostname (e.g. `yourname.duckdns.org`) that always points at it, so
your devices can always find home. Free.

**How to get your domain + token:**
1. Go to **https://www.duckdns.org**
2. Click a **"sign in with"** button at the top (Google, GitHub, Reddit, or
   Twitter — uses an account you already have; the project never sees it).
3. In the **"add domain"** box, type a name (e.g. `yourname`) and click
   **add domain** → you now own `yourname.duckdns.org`.
4. Copy the **token** shown near the top of the page (a long UUID like
   `a1b2c3d4-5678-90ab-cdef-1234567890ab`).
5. Put both in your `config.env` as `DUCKDNS_DOMAIN` (just the subdomain part)
   and `DUCKDNS_TOKEN`. The `duckdns-update.sh` timer keeps it current.

*Alternatives:* if you have a **static public IP** from your ISP you can skip
DuckDNS entirely, or use another dynamic-DNS provider (No-IP, Cloudflare, etc.)
— you'd just point clients at that hostname instead.

### 4. Your router (port-forwarding)
**What:** not software to install, but you need admin access to your home
router to forward **one UDP port** (default `51820`) to the hub. See
[`ROUTER.md`](ROUTER.md). Every router has this under *Port Forwarding* /
*Virtual Server* / *NAT*.

---

## Installed automatically by the scripts

You don't fetch these yourself — `bootstrap.sh` installs them via `apt` on the
hub. Listed here so you know what's landing on the box:

- **wireguard / wireguard-tools** — the VPN itself. (Debian package.)
- **qrencode** — turns client configs into scannable QR codes.
- **iptables** — the NAT rules that let clients reach the internet + your LAN.
- **curl** — used by the DuckDNS updater.

All are standard packages from your distro's official repositories.

---

## Optional

### Pi-hole — network-wide ad/tracker blocking
**What:** a DNS-based ad blocker; with it, every device on the VPN gets ad
blocking. Free and open-source.
**How:** run `server/pihole-setup.sh` on the hub. It uses **Pi-hole's official
unattended installer**, which downloads and runs a script from
**https://install.pi-hole.net** (project site: https://pi-hole.net). If you'd
rather review it first, read that installer before running the setup script.

### A cloud VPS — Phase 2 exit node
**What:** a cheap always-on cloud server so your traffic can exit from an IP
that isn't your house. See [`PHASE2-vps-exit.md`](PHASE2-vps-exit.md).
**Where (any of these; pick one):**
- Hetzner Cloud — https://www.hetzner.com/cloud (~€4/mo, cheapest)
- DigitalOcean — https://www.digitalocean.com (~$4–6/mo)
- Vultr — https://www.vultr.com (~$5/mo)

**How:** create an account, spin up the **smallest Debian 12** instance, note
its public IP, open **UDP 51820** in the provider's firewall, then run
`vps/bootstrap-exit.sh` on it. (This step does require a payment method with
the provider.)

### Tor Browser — Phase 3 anonymity
**What:** for truly unlinkable browsing (privacy ≠ anonymity — see
[`PHASE3-tor.md`](PHASE3-tor.md)). Free.
**Where:** the official site only — **https://www.torproject.org/download/**

---

## For contributors (not needed to just run it)
- **ShellCheck** — lints the scripts. https://www.shellcheck.net (or
  `sudo apt install shellcheck`). CI runs it automatically via GitHub Actions.
