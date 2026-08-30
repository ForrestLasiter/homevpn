# Contributing

Thanks for looking! This is a small, script-first project — the goal is that
anyone can clone it and stand up their own VPN.

## Ground rules
- **Never commit secrets.** No private keys, no `config.env`, no `*.env`, no
  device configs. `.gitignore` guards these — don't work around it.
- **Keep scripts POSIX-bash and `set -euo pipefail`.** They run on plain Debian.
- **Shell scripts stay LF + executable.** `.gitattributes` enforces LF; mark new
  scripts executable with `git update-index --chmod=+x path/to/script.sh`.
- **Lint before pushing:** `shellcheck server/*.sh proxmox/*.sh vps/*.sh`
  (CI runs the same). Locally you can also just `bash -n script.sh`.

## Adding a setting
Put it in `config.env.example` with a comment, and read it in the script via
`VAR="${VAR:-default}"` so the default still works when it's unset.

## Testing without hardware
Most logic can be exercised on any Linux box or WSL. Anything that needs a real
Proxmox host, router port-forward, or VPS is marked 🧊 in `ROADMAP.md`.
