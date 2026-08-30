# Router setup — the one thing outside the container

Your VPN clients dial home from the outside world. For that to work, your
router has to send WireGuard's traffic to the hub container. Two settings:

## 1. Port forward (required)

Forward **one UDP port** to the hub container:

| Setting | Value |
|---|---|
| Protocol | **UDP** (not TCP) |
| External / WAN port | `51820` |
| Internal / LAN port | `51820` |
| Destination / target IP | the hub container's LAN IP (e.g. `192.168.1.10`) |

Where to find it: router admin page → *Port Forwarding* / *Virtual Server* /
*NAT* (name varies by brand). If you set `NET_IP` to a static address in
`create-lxc.sh`, use that. If you used DHCP, also add a **DHCP reservation**
so the container's IP never changes.

> Changing the port? Change `WG_PORT` in `bootstrap.sh` too, re-run it, and
> re-issue client configs.

## 2. Confirm you're not behind CGNAT (2-minute check)

If your ISP puts you behind carrier-grade NAT, inbound port forwards silently
do nothing — you'd need the Phase 2 cloud VPS as the entry point instead.

Check: compare these two numbers.

- **Your router's WAN IP** — in the router admin page, under *Status* / *WAN*.
- **Your actual public IP** — visit https://ifconfig.me or run:
  ```bash
  curl https://api.ipify.org
  ```

- **They match** → you're fine, port forwarding will work. ✅
- **They differ**, or the router WAN IP starts with `100.64.`–`100.127.` →
  you're behind CGNAT. Port forwarding won't work; ping me and we'll do the
  VPS-entry design (`docs/PHASE2-vps-exit.md`). ⚠️

## 3. Test from off-network

Easiest test: put a phone on **cellular** (Wi-Fi OFF), import its config,
toggle the tunnel on. If it connects and you can browse, the forward is good.
From a laptop you can also probe the port:

```bash
# from OUTSIDE your home network
nc -u -z -v YOURNAME.duckdns.org 51820
```

(WireGuard is silent by design, so the truest test is a real client
connecting — not a port scanner.)
