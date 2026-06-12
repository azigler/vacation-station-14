# Session handoff — 2026-06-12 (prod-outage triage + restore)

## State at offboard

- **Current branch**: main
- **Last commit**: `e4daf50bdb` — `:card_file_box: beads: close vs-byi — prod outage resolved, join confirmed` (this offboard commit follows)
- **Open beads**: ~29 (1 P1 epic; new: **vs-f6i P2** queued as top pick); in-progress: vs-4h1
- **In-flight subagents**: none (no dispatches this session — all ops work done directly per maintainer authorization)
- **Dirty files**: none after offboard commit
- **Markers**: `.offboard-pending` n/a (clean session)

## What happened this session

**Prod outage found and fixed (vs-byi, P1, CLOSED — maintainer confirmed join works).**
Andrew reported "unknown server error occurred during handshake" on connect.

- **Root cause**: pico (Mac Studio; hosts postgres/web/CDN/obs/static since the
  2026-05-24 zig-zone migration, commit `db90b39480`, runbook
  `~/explore/.claude/skills/zig-zone/SKILL.md`) **rebooted ~2026-05-29 and nothing
  restarted** — headless Mac = no GUI login = no `gui/501` launchd domain, so brew
  services and LaunchAgents silently never load. Game server on zig-computer failed
  every handshake at the ban check (Npgsql → pico:5432 refused). Sat silent ~2 weeks
  (zero players since 05-25).
- **Restored on pico** (via `ssh pico` — port-2222 alias in `~/.ssh/local`; tailscale
  SSH from zig-computer is grammatically impossible: tagged src → user-owned dst):
  postgres@17 (`launchctl bootstrap user/501`), colima (6 containers auto-resumed
  healthy), nginx (`launchctl kickstart system/...` — bootstrap err 5 = already
  loaded), vs14-web (**nohup fallback** — its agent refuses bootstrap, err 5 even
  via sudo; NOT reboot-durable).
- **Verified**: DB intact (round 25, zero data loss), app role connects from
  zig-computer; public paths all 200 (/, /maps, /recipes, /guidebook, /nurseshark,
  /admin); maintainer joined successfully. Game server needed no restart (Npgsql
  pool recovers per-connection).
- **Architecture confirmed for the maintainer**: game server + watchdog stay on
  zig-computer (direct public UDP, real source IPs — Phase 4 SS14-on-pico was
  rolled back, `dotfiles-hdo`); only the DB path crosses the tailnet, over TCP.
  Server uses **ACZ** — CDN is not in the join path.
- **Filed vs-f6i (P2)**: pico boot-resilience. Also updated memory
  (`project_publishing.md`) with the pico-era failure mode + ops cheatsheet.

## What's next

1. **vs-f6i** (queued by maintainer — top pick): make pico services reboot-proof;
   **DB backups dead since 2026-05-24** (scariest sub-item — verify
   `com.zig.ss14-backup` on pico actually fires, or re-enable zig-computer's
   `ss14-backup.timer` against the tailnet DB); fix loki shipping (container binds
   127.0.0.1:3100, watchdog ships to pico:3100 → refused); investigate vs14-web
   bootstrap err 5; update stale docs (services SKILL.md + CLAUDE.md claim local
   pg16 + local docker — reality is pico).
2. **vs-2f8.8 re-thaw decision** — third consecutive silent outage; every one was
   catchable by a single external probe. Strong evidence; maintainer call.
3. vs-4h1 parent close check, vs-2f8.10/.11 — unchanged from prior handoff.

## Warnings / watch-outs

- **vs14-web on pico runs via nohup** — dies on next pico reboot/process kill.
  First casualty of the next incident unless vs-f6i lands.
- **No DB backups since 2026-05-24.** Do no risky DB work before fixing this.
- **`ssh pico` (port 2222) is the ONLY path from zig-computer to pico.** Don't
  burn time on tailscale SSH (ACL grammar can't express it — see
  `~/dotfiles/tailscale/acl.jsonc` comment block).
- **Headless-Mac launchd**: `brew services start` always fails (no gui domain);
  use `launchctl bootstrap user/501 <plist>` / `kickstart system/<label>`.
  Bootstrap "error 5" usually = already loaded → kickstart.
- **Two clones can drift**: changes touching `ops/*/build.sh`, build-pipeline
  submodules, or `web/` must also be pulled on pico
  (`/Users/pico/vacation-station-14`).
- Prior handoff's warnings (`.env.secrets` discipline, `ops/cdn/` forbidden path,
  publish-testing cron OFF, vs-i9u/vs-qd5/vs-xvp.6 blocks) all still stand.
