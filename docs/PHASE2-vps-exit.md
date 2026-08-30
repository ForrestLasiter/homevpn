# Phase 2 — cloud VPS exit node (privacy / "not my house" IP)

> Not built yet. This is the plan for when Phase 1 is proven and you want
> your traffic to exit somewhere other than your home residential IP.

## Why

Phase 1 (home hub) protects you on untrusted Wi-Fi and gives you your LAN
back — but everything exits via **your home IP**, which is uniquely yours.
For "hide my traffic behind an IP that isn't me," you add a cheap always-on
VPS and make *it* the exit.

**Honest limit:** this is *pseudonymity*, not anonymity. The VPS IP traces
to whoever rented it (you, via a card). It defeats casual/local observation
and ties your traffic to a datacenter instead of your doorstep — it does not
defeat a determined party who can subpoena the provider. For true anonymity,
that's Tor (Phase 3).

## Topology

```
        phone / laptop
             │  (WireGuard)
             ▼
   ┌─────────────────────┐        ┌──────────────────────┐
   │  Home hub (Proxmox) │◀──────▶│   VPS exit (cloud)    │──▶ internet
   │  10.10.10.1         │  wg    │   exits here          │
   │  + Pi-hole, LAN     │        │   e.g. Hetzner €4/mo  │
   └─────────────────────┘        └──────────────────────┘
```

Two workable shapes — we'll pick when we get here:

1. **Client picks the exit.** Devices keep the home peer for LAN/DNS and
   add the VPS as a second peer; full-tunnel traffic routes to the VPS.
   Most flexible: flip exits per device.
2. **Hub routes through VPS.** The home hub forwards internet-bound client
   traffic up to the VPS. Clients keep one simple config; you choose the
   exit centrally.

## Shopping list (for later)

- A small VPS (1 vCPU / 1 GB is plenty): Hetzner, DigitalOcean, Vultr.
- The same `wireguard` stack — we'll reuse `bootstrap.sh`, adapted so the
  VPS is an exit peer rather than a hub.
- ~10 minutes once the box exists.

## Phase 3 (optional) — Tor for real anonymity

For the sessions that truly need it, route through Tor rather than the VPN:
Tor Browser on the device, or a `tor` transparent-proxy peer. Slow, but no
IP traces back to you. Kept separate on purpose — you turn it on only when
the threat model calls for it.
