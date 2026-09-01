# Phase 3 (built) — Whonix on Proxmox for anonymity

> This is the *realized* build of the Whonix option from [`PHASE3-tor.md`](PHASE3-tor.md).
> Two Whonix VMs on Proxmox: a **Gateway** that forces all traffic through Tor,
> and a **Workstation** (LXQt desktop) whose only network path is through the
> Gateway — so it physically cannot leak your real IP. Verified working with
> obfs4 bridges.

**Reality check:** this gives strong anonymity (what journalists/activists use),
not a guarantee against a global adversary. Anonymity is mostly *behavior* — see
the rules in [`PHASE3-tor.md`](PHASE3-tor.md).

---

## What you need
- Proxmox VE (this was built on 9.2), ~15 GB free, 4 GB RAM to spare.
- The Whonix KVM image (LXQt for a desktop): https://www.whonix.org/wiki/KVM

## 1. Download + VERIFY the image (do not skip verification)
```bash
mkdir -p /root/whonix && cd /root/whonix
BASE=https://download.whonix.org/libvirt/<VERSION>
IMG=Whonix-LXQt-<VERSION>.Intel_AMD64.qcow2.libvirt.xz
curl -fL -O "$BASE/$IMG"; curl -fL -O "$BASE/$IMG.asc"
curl -fsSL https://www.whonix.org/keys/derivative.asc | gpg --import
gpg --verify "$IMG.asc" "$IMG"     # must say: Good signature (Patrick Schleizer)
tar -xf "$IMG"                     # -> Whonix-Gateway-*.qcow2 + Whonix-Workstation-*.qcow2
```

## 2. Two Proxmox bridges
The Whonix images expect two networks. On Proxmox, add to `/etc/network/interfaces`:

```ini
# Internal: isolated L2 link, Gateway <-> Workstation only (no uplink)
auto vmbr9
iface vmbr9 inet manual
        bridge-ports none
        bridge-stp off
        bridge-fd 0

# External: the 10.0.2.0/24 NAT network the Whonix image hard-codes.
# *** THE KEY GOTCHA ***: Whonix's external NIC is fixed at 10.0.2.15 with
# gateway 10.0.2.2 (libvirt user-mode net). A plain bridge to your LAN has no
# 10.0.2.2, so Tor gets "No route to host". This makes the host BE 10.0.2.2 and
# NAT it to the internet, so the image works unmodified.
auto vmbr10
iface vmbr10 inet static
        address 10.0.2.2/24
        bridge-ports none
        bridge-stp off
        bridge-fd 0
        post-up   sysctl -q -w net.ipv4.ip_forward=1
        post-up   iptables -t nat -C POSTROUTING -s 10.0.2.0/24 -o vmbr0 -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.0.2.0/24 -o vmbr0 -j MASQUERADE
        post-up   iptables -C FORWARD -i vmbr10 -o vmbr0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -i vmbr10 -o vmbr0 -j ACCEPT
        post-up   iptables -C FORWARD -i vmbr0 -o vmbr10 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -A FORWARD -i vmbr0 -o vmbr10 -m state --state RELATED,ESTABLISHED -j ACCEPT
```
Then `ifreload -a`. (Replace `vmbr0` with your Proxmox uplink bridge if different.)

## 3. Create the VMs (host shell)
```bash
LVM=local-lvm
# Gateway: net0 = external NAT (vmbr10), net1 = internal (vmbr9)
qm create 105 --name Whonix-Gateway --memory 2048 --cores 1 --cpu host \
  --machine q35 --ostype l26 --scsihw virtio-scsi-single \
  --net0 virtio,bridge=vmbr10 --net1 virtio,bridge=vmbr9 \
  --vga virtio --tablet 1 --onboot 0
qm importdisk 105 Whonix-Gateway-*.qcow2 $LVM
qm set 105 --virtio0 $LVM:vm-105-disk-0 --boot order=virtio0

# Workstation: net0 = internal ONLY (vmbr9). virtio-gpu display is important.
qm create 106 --name Whonix-Workstation --memory 3072 --cores 1 --cpu host \
  --machine q35 --ostype l26 --scsihw virtio-scsi-single \
  --net0 virtio,bridge=vmbr9 --vga virtio --tablet 1 --onboot 0
qm importdisk 106 Whonix-Workstation-*.qcow2 $LVM
qm set 106 --virtio0 $LVM:vm-106-disk-0 --boot order=virtio0

qm start 105 && sleep 30 && qm start 106
```

> **Display gotcha:** use `--vga virtio` (virtio-gpu), **not** `std`. With `std`
> the LXQt desktop renders once then freezes in the noVNC console (stopped clock,
> dead mouse). `--tablet 1` gives an accurate mouse pointer in the console.

## 4. First boot + connect Tor
- Use each VM through the **Proxmox web console** (noVNC).
- Whonix 18 uses **user/sysmaint split**: the `user` account **cannot `sudo`**
  (by design — "permission denied: sudo" is expected). For admin tasks, reboot
  and pick **"PERSISTENT Mode | SYSMAINT Session"** in the boot menu.
- Tor connects automatically. Verify on the Gateway: `systemcheck` → *"Connected
  to Tor."* Then on the Workstation open **Tor Browser** → `check.torproject.org`
  → *"Congratulations… configured to use Tor"* (the IP shown is a Tor exit, not
  yours).

## 5. Hardening
- **Tor Browser → Safest:** shield icon → Settings → Security Level → *Safest*.
- **obfs4 bridges** (hide that you use Tor from your ISP): boot the Gateway into
  **SYSMAINT** → System Maintenance Panel → **Anon Connection Wizard** →
  *Configure* → *I need bridges* → **obfs4** → no proxy → apply. Tor reconnects
  through a few disguised bridge IPs instead of obvious relay connections.
- **Updates:** SYSMAINT → System Maintenance Panel → **Install Updates** (runs
  over Tor; slow but important).

## 6. Using it remotely
Don't give the Workstation a direct/LAN NIC — that creates a non-Tor path and
defeats the isolation. Instead reach it through the **Proxmox web console over
your WireGuard VPN**: connect the VPN, open `https://<proxmox>:8006`, open the
Workstation console. For a real terminal without breaking anonymity, publish an
**SSH onion service** on the Workstation and SSH to it through Tor.

## Gotchas recap
| Symptom | Cause | Fix |
|---|---|---|
| Tor stuck 5%, "No route to host" | external NIC wants gw `10.0.2.2` | the `vmbr10` NAT bridge above |
| Desktop freezes after login (stopped clock) | `std` VGA | `--vga virtio` |
| Mouse won't click in console | no absolute pointer | `--tablet 1` |
| `sudo` / `passwd` "permission denied" | user/sysmaint split | boot SYSMAINT session |
| systemcheck "degraded" (emerg-shutdown) | VM has no boot media | harmless, ignore |
