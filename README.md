# homevpn — a self-hosted WireGuard hub

Your own VPN, run on your Proxmox box. Encrypts your traffic on untrusted
Wi-Fi, gives you your home network from anywhere, meshes your devices, and
(with Pi-hole) blocks ads/trackers on every device.

Built for: **Windows 11 PC, Android, iPhone/iPad, Linux machines.**

> ### Read this first: privacy vs. anonymity
> This gives you **privacy and control**, not **anonymity**. Traffic exits
> through your **home IP**, which is uniquely yours — fine for security on
> hostile Wi-Fi and for reaching home, but it does **not** hide who you are.
> To exit behind a different IP, add the cloud node in
> [`docs/PHASE2-vps-exit.md`](docs/PHASE2-vps-exit.md). For real anonymity,
> that's Tor ([`docs/PHASE3-tor.md`](docs/PHASE3-tor.md)). This is **Phase 1**.

See [`ROADMAP.md`](ROADMAP.md) for the full multi-phase plan.

> 📋 **New here? Read [`docs/PREREQUISITES.md`](docs/PREREQUISITES.md) first** —
> it lists every third-party site and piece of software you'll touch (Proxmox,
> the WireGuard apps, DuckDNS, Pi-hole, an optional VPS, Tor), what each costs,
> and exactly how to get it. Phase 1 is entirely free.

---

## What's in here

```
homevpn/
├── config.env.example        # copy to config.env — one file, all settings
├── proxmox/create-lxc.sh     # run on the Proxmox HOST — makes the container
├── server/                   # run INSIDE the container:
│   ├── bootstrap.sh          #   stand up the WireGuard hub
│   ├── add-client.sh         #   enroll a device (+QR)
│   ├── list-clients.sh       #   who's enrolled + online now
│   ├── show-client.sh        #   re-print a device's config / QR
│   ├── remove-client.sh      #   revoke a device
│   ├── status.sh             #   one-glance health check
│   ├── backup.sh             #   back up / restore keys + config
│   ├── uninstall.sh          #   tear it back down
│   ├── pihole-setup.sh       #   network-wide ad blocking
│   └── duckdns-update.sh     #   keep home reachable as your IP changes
├── vps/                      # Phase 2 — run ON A CLOUD VPS:
│   ├── bootstrap-exit.sh     #   turn a VPS into a not-your-house exit
│   └── add-exit-client.sh    #   enroll a device on the exit
├── docs/
│   ├── PREREQUISITES.md      # every third-party site/app + how to get it
│   ├── ROUTER.md             # the one port-forward you must do
│   ├── PHASE2-vps-exit.md    # the cloud exit node
│   └── PHASE3-tor.md         # Tor, for real anonymity
└── clients/                  # generated device configs land here (git-ignored)
```

---

## Setup — in order

### 0. Before you start
- Make a free DuckDNS domain: https://www.duckdns.org → sign in → pick a
  subdomain → copy the **token**. (Handles your changing home IP.)
- Know your home LAN subnet (looks like `192.168.1.0/24`). On the Proxmox
  host: `ip route | grep -v wg | grep /`.
- **Set your options once** — copy the template and edit it; every script
  reads it, so you don't hand-edit each one:
  ```bash
  cd homevpn
  cp config.env.example config.env
  nano config.env      # HOME_LAN, DUCKDNS_DOMAIN, DUCKDNS_TOKEN, etc.
  ```
  (`config.env` is git-ignored — it holds your token, so it never gets
  committed.)

### 1. Create the container (on the Proxmox host)
Copy this folder to your Proxmox host, then:
```bash
cd homevpn/proxmox
./create-lxc.sh          # reads ../config.env; also copies it into the container
```
This makes a small Debian 12 LXC, gives it the TUN device WireGuard needs,
and copies the `server/` scripts (and your `config.env`) inside to `/opt/wg-hub`.

### 2. Stand up the hub (inside the container)
```bash
pct enter <CTID>          # CTID printed by the previous step (default 910)
cd /opt/wg-hub
./bootstrap.sh            # picks up the config.env that came with it
```
> Didn't use `config.env`? Then edit the settings block at the top of
> `bootstrap.sh` first (`HOME_LAN`, `DUCKDNS_DOMAIN`, `DUCKDNS_TOKEN`).
When it finishes it prints the hub's public key and the endpoint your
devices will use (`YOURNAME.duckdns.org:51820`).

### 3. Forward the port on your router
Forward **UDP 51820** to the container's LAN IP. Full walkthrough +
CGNAT check in [`docs/ROUTER.md`](docs/ROUTER.md). **The VPN can't be
reached from outside until this is done.**

### 4. (Optional but you wanted it) Ad blocking
```bash
PIHOLE_PASSWORD='pick-a-good-one' ./pihole-setup.sh
```
Now every VPN device gets ad/tracker blocking via DNS, admin UI at
`http://10.10.10.1/admin` once you're connected.

### 5. Add your devices
```bash
./add-client.sh windows-pc      # full-tunnel (all traffic) — default
./add-client.sh pixel           # phone: scan the QR it prints
./add-client.sh ipad
./add-client.sh wellspring-lt split   # split-tunnel: only home LAN + VPN
```
- **full** (default) = all traffic through home → privacy on any network.
- **split** = only home LAN + other VPN devices go through the tunnel;
  normal browsing stays on the local connection.

---

## Installing each device

**Windows 11 PC**
1. Install the WireGuard app (https://www.wireguard.com/install/).
2. Get the config text: on the Proxmox host,
   `pct pull <CTID> /etc/wireguard/clients/windows-pc.conf windows-pc.conf`
   — or just `cat` it inside the container and copy the text.
3. WireGuard → *Add Tunnel* → *Add empty tunnel* → paste → Save → Activate.

**Android / iPhone / iPad**
1. Install "WireGuard" from the Play Store / App Store.
2. In the app: **+** → *Create from QR code* → scan the QR that
   `add-client.sh` printed. Name it, toggle on. Done.

**Linux (WellSpring / others)**
```bash
sudo apt install wireguard        # or your distro's package
sudo cp wellspring-lt.conf /etc/wireguard/wg0.conf
sudo wg-quick up wg0              # start now
sudo systemctl enable wg-quick@wg0   # start on boot
```

---

## Everyday use

All of these run inside the hub container (`pct enter <CTID>`, `cd /opt/wg-hub`):

| I want to… | Do this |
|---|---|
| Add another device | `./add-client.sh <name> [full\|split]` |
| List devices + who's online | `./list-clients.sh` |
| Re-print a device's config/QR | `./show-client.sh <name>` |
| Revoke a device | `./remove-client.sh <name>` |
| Health check | `./status.sh` |
| Back up keys + config | `./backup.sh /some/safe/dir` |
| Restart the tunnel | `systemctl restart wg-quick@wg0` |
| Rotate ad-block password | re-run `pihole-setup.sh` with a new `PIHOLE_PASSWORD` |
| Tear it all down | `./uninstall.sh` (add `--purge` to wipe keys) |

---

## Phase 2 — exit behind a not-your-house IP

When Phase 1 is proven and you want traffic to leave from somewhere other than
your home IP, rent a cheap VPS and run, **on the VPS**:
```bash
./vps/bootstrap-exit.sh        # reads config.env (VPS_WG_* settings)
./vps/add-exit-client.sh laptop
```
Keep both tunnels on your device and flip to the VPS one when you want the
different exit. Read [`docs/PHASE2-vps-exit.md`](docs/PHASE2-vps-exit.md) first —
this is **pseudonymity, not anonymity**. For real anonymity, see
[`docs/PHASE3-tor.md`](docs/PHASE3-tor.md).

---

## Troubleshooting

- **Handshake never completes (client shows "handshake … never").**
  Router port-forward missing/wrong, or you're behind CGNAT — see
  [`docs/ROUTER.md`](docs/ROUTER.md).
- **Connected but no internet (full-tunnel).** IP forwarding / NAT — re-run
  `bootstrap.sh`; confirm `WAN_IF` was detected (it prints it).
- **Connected but can't reach home devices (split-tunnel).** `HOME_LAN` in
  `bootstrap.sh` doesn't match your real LAN subnet. Fix it, re-run, re-issue
  configs.
- **DuckDNS not updating.** Inside the container:
  `/usr/local/bin/duckdns-update.sh` and read the error; check
  `/etc/duckdns.env`.
- **WireGuard won't start in the LXC** (`RTNETLINK`/`Cannot open TUN`). The
  container is missing the TUN device — the `create-lxc.sh` step adds it;
  make sure `wireguard` is `modprobe`'d on the Proxmox host.

---

## Security notes
- Private keys are generated **on the box they belong to** and never leave it;
  `clients/*.conf` (which hold client private keys) live at mode `600` — treat
  them like passwords, delete after importing to the device.
- Each peer also gets a **pre-shared key** (extra post-quantum-ish layer).
- Pi-hole is bound to the VPN interface only — never an open internet resolver.
- Nothing here logs your browsing (Pi-hole query logging is local and you can
  turn it off in its UI).
