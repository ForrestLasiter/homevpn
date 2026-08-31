# Connecting a device to the VPN

Once a device has been **enrolled** on the hub (an admin ran
`server/add-client.sh <name>`, which produced either a **`.conf` file** or a
**QR code**), connecting it is a two-minute job. This guide covers the four
common platforms.

**You need two things per device:**
1. The **WireGuard app** for that platform — see
   [`PREREQUISITES.md`](PREREQUISITES.md) for official download links.
2. That device's **config** — a `.conf` file (Windows/Linux) or a QR code
   (phones/tablets). Treat it like a password; each config is for one device.

> **Full-tunnel vs split-tunnel** — if the config's `AllowedIPs` is
> `0.0.0.0/0, ::/0` it's **full-tunnel**: *all* traffic goes through home
> (privacy everywhere). If it lists your home subnet instead (e.g.
> `10.10.10.0/24, 192.168.1.0/24`) it's **split-tunnel**: only home + VPN
> traffic goes through, normal browsing stays local. Our default is full-tunnel.

---

## Windows PC

1. Install **WireGuard for Windows** from https://www.wireguard.com/install/.
2. Get your `windows-pc.conf` onto the PC (it was sent to you separately).
3. Open **WireGuard** → **Import tunnel(s) from file** (bottom of the left
   panel, or the ▾ arrow next to *Add Tunnel*) → pick the `.conf`.
   *(Alternatively: **Add empty tunnel** and paste the config text.)*
4. Click **Activate**. The status turns green and shows a handshake within a
   few seconds.
5. To disconnect, click **Deactivate**. The tunnel stays listed for next time.

**Auto-connect (optional):** Edit the tunnel → check *"Block untunneled
traffic (kill-switch)"* if you want traffic blocked whenever the VPN drops.

---

## Android

1. Install **WireGuard** from the Play Store (by *WireGuard Development Team*).
2. Open the app → tap the **➕** (bottom right) → **Scan from QR code**.
3. Point it at your device's QR code. Give the tunnel a name (e.g. `home`) and
   save.
4. Flip the toggle **on**. First connect may ask to allow a VPN connection —
   accept.
5. Toggle off to disconnect.

*No QR? Choose **Import from file or archive** instead and pick the `.conf`.*

---

## iPhone / iPad

1. Install **WireGuard** from the App Store (by *WireGuard Development Team*).
2. Open the app → **Add a tunnel** → **Create from QR code**.
3. Scan your device's QR code, name the tunnel, and allow the VPN
   configuration when iOS prompts (Face ID/passcode).
4. Toggle the tunnel **Active** on. You'll see it in the status bar.
5. Toggle off to disconnect.

*No QR? Use **Create from file or archive** and pick the `.conf` (e.g. from
Files/iCloud).*

*iPhone **and** iPad need **separate** configs — the same one can't be active
on both at once.*

---

## Linux PC

Two ways — a GUI if your desktop has one, or the command line.

**Command line (works everywhere):**
```bash
sudo apt install wireguard            # Debian/Ubuntu; use your distro's pkg otherwise
sudo cp linux.conf /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/wg0.conf
sudo wg-quick up wg0                   # connect now
sudo systemctl enable wg-quick@wg0     # (optional) reconnect on every boot
```
- Check it: `sudo wg` (shows the latest handshake and transfer).
- Disconnect: `sudo wg-quick down wg0`.

**GNOME/KDE GUI (optional):** Settings → Network → VPN → **+** → *Import from
file…* → pick `linux.conf` → toggle on.

---

## Confirm it's actually working

1. **Handshake:** the app should show a *latest handshake* a few seconds after
   connecting, and data sent/received climbing.
2. **Your IP changed (full-tunnel):** visit **https://ifconfig.me** or
   https://whatismyipaddress.com — it should show your **home** public IP,
   not the coffee-shop/cellular one.
3. **Best real test:** connect with the device on **cellular / a different
   Wi-Fi** (not your home network) and confirm you can still browse and reach
   home. That proves remote access, not just LAN.

---

## Everyday tips

- **Leave it on:** full-tunnel is safe to leave connected all day; that's the
  point — every network you join is then encrypted through home.
- **Battery:** WireGuard is light. `PersistentKeepalive = 25` keeps the tunnel
  alive through NAT with negligible drain.
- **A second phone/tablet:** it needs its **own** config — ask the admin to run
  `add-client.sh <name>` (or `show-client.sh <name>` to re-print an existing
  one).
- **Lost/old device:** the admin runs `remove-client.sh <name>` to revoke it
  instantly.

---

## Quick troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Connects but **no internet** | full-tunnel NAT issue on the hub — tell the admin (`status.sh` on the hub) |
| **Handshake never happens** | you're not reaching the hub — router port-forward or DNS; admin checks `docs/ROUTER.md` |
| Works on Wi-Fi at home, not outside | that's the port-forward/remote-reachability piece — admin issue, not your device |
| Can reach internet but **not home devices** | split-tunnel with the wrong home subnet — admin re-issues the config |
| IP didn't change on `ifconfig.me` | tunnel isn't actually active, or it's a split-tunnel config (by design) |
