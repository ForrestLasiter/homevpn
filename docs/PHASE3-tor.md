# Phase 3 — Tor, for real anonymity

> Not built yet — this is the design + the honest trade-offs. Phase 1 gives you
> privacy; Phase 2 gives you a not-your-house exit IP (pseudonymity); **Tor is
> the only piece here that aims at true anonymity.**

## When you actually want this
Use Tor when the goal is "nothing traces back to me," not just "encrypt my
Wi-Fi." It is **slow** and some sites block Tor exit nodes, so it's a
per-session tool, not your everyday tunnel. Run the VPN for daily privacy and
reach for Tor only for the sessions that need to be unlinkable.

## Three ways to do it, cheapest → most integrated

### 1. Tor Browser on the device (recommended default)
Just install the Tor Browser. It routes only that browser through Tor, leaks
the least, and needs zero server work. Works alongside the VPN — VPN encrypts
the local hop, Tor anonymizes the browsing. **Start here.**

### 2. VPN → Tor on the hub (a `tor` peer)
Run `tor` on the hub and hand clients a route that sends chosen traffic into
Tor's transparent proxy (`TransPort`/`DNSPort`). Everything for that client
exits via Tor without installing anything on the device. More moving parts, and
misconfig can leak — so this is a deliberate, tested add-on, not a default.

### 3. Tails / Whonix for the highest bar
For threat models where the OS itself must not leak, that's a separate live OS
(Tails) or isolation VM (Whonix), outside this repo's scope. Noted for
completeness.

## The order that matters
- **You → VPN → Tor** (what this repo would do): your ISP sees "encrypted VPN
  traffic," the VPN sees "traffic going into Tor," Tor anonymizes the exit.
  Good default.
- **You → Tor → VPN** (VPN after Tor): rarely what you want here; ties your
  anonymous session back to your paid VPN. Skip unless you have a specific
  reason.

## Reality check
Tor is strong but not magic: browser fingerprinting, logging into a personal
account, or leaking DNS all de-anonymize you regardless of Tor. If it matters,
use the Tor Browser as-is (don't resize it, don't install plugins, don't log
into your real accounts) — that's what its defaults are hardened for.
