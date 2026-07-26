# Session handoff — 2026-07-12 6d5bf5a7 (game-server shutdown + pico rogue-stack cleanup)

## State at offboard
- **Current branch**: main
- **Last commit**: `2d1c8370b0` — `:card_file_box: beads: vs-tjj CDN-hang bug + vs-f6i note …` (this offboard commit follows)
- **Open beads**: 30 (1 P1 epic; new this session: **vs-tjj** P2 bug); in-progress: vs-4h1
- **In-flight subagents**: none (all ops done directly, per maintainer authorization — no dispatches)
- **Dirty files**: `.gitattributes` (M) — **NOT this session's**: a pre-existing, correct one-line
  dedup (removes superseded `.beads/*.jsonl merge=union`, keeps `merge=jsonl-union`). Left
  uncommitted deliberately; next session can commit it if desired.
- **Markers**: `.offboard-pending` cleared

## What happened this session

Pure ops session (no code). Maintainer (Zig) asked to turn off the SS14 game server on
zig-computer to reclaim RAM + stop it returning on reboot. That expanded into a topology
audit and two pico fixes.

1. **zig-computer game server OFF (maintainer request).** `ss14-watchdog.service` (= watchdog
   + game-server child) **stopped + `disable`d**; the game-server child orphaned on stop
   (unit `KillMode` only kills the watchdog) so SIGTERM'd it explicitly. `ss14-replay-rotate.timer`
   also stopped + disabled. **~1 GB RAM reclaimed**, UDP 1212 unbound. Re-enable ONLY on explicit
   request: `sudo systemctl enable --now ss14-watchdog.service`.

2. **Verified the zig-computer ↔ pico split** (Zig didn't remember it). zig-computer
   (`51.81.33.136`) = public TLS edge only: nginx vhost `vs14.zig.computer.conf` routes
   `/instances/ /client.zip /watchdog/` → local watchdog `:5000`, **everything else →
   `pico.tailfb4637.ts.net:8080`**. pico (headless Mac, `ssh pico` port 2222, tailnet
   `100.72.47.4`) holds ALL content+state: 6 colima containers (cdn/mapserver/ss14-admin/
   grafana/loki/prometheus), native postgres (LIVE `vacation_station` DB the server uses),
   vs14-web, static builds. zig-computer also has a **stale local postgres** (127.0.0.1:5432,
   `vacation_station`+`_mapserver` DBs) that nothing uses.

3. **Rogue 2nd game server on pico — SHUT DOWN.** Digging into a `/cdn/` outage found a native
   launchd stack (`com.zig.ss14-watchdog` → `Robust.Server`, + `com.zig.ss14-wrapper`) — the
   never-torn-down Phase-4 "SS14-on-pico" leftover — running since Jun 28, **~3 GB RAM + 14.6%
   CPU**, joinable by nobody. `launchctl bootout gui/501/…` + `disable`d both (plists remain at
   `~/Library/LaunchAgents/`, disabled). pico 27G→24G used, load 2.6→1.4.

4. **Hung vs14-cdn container — RESTARTED.** Showed "Up 4 weeks" but app dead (`curl :8087`
   timed out) → `/cdn/` returned 000. `docker restart vs14-cdn` → `/cdn/` now fast 404 (healthy;
   empty until publish flow lands). Same class as the April CDN outage.

5. **Recorded:** filed **vs-tjj** (CDN-hang bug → re-thaw vs-2f8.8 monitoring as the guard);
   noted **vs-f6i** (don't re-enable the disabled pico agents); updated memory
   (`project_publishing.md` + `MEMORY.md`) so the intentionally-off servers aren't misread as
   an outage.

Verified all pico-served public paths 200 throughout (`/ /maps /admin /nurseshark /recipes /guidebook`).

## What's next

1. **vs-f6i** (pico boot-resilience) — still the top ops item. Now also carries: game server is
   intentionally off, and the two pico game-server agents are intentionally `disable`d — do NOT
   re-enable them when wiring boot-resilience. Backup (`com.zig.ss14-backup`) left intact.
2. **vs-tjj / vs-2f8.8 re-thaw** — the CDN hang (2nd occurrence) would've been caught by a single
   blackbox HTTP probe; vs-2f8.8 was scoped to exclude the CDN. Expand it to cover vs14-cdn.
3. **Optional cleanup** — the stale local postgres on zig-computer (`vacation_station` DBs nothing
   uses). Offered to Zig; not chosen this session.

## Warnings / watch-outs

- **BOTH game servers are now intentionally OFF + disabled** (zig-computer `ss14-watchdog.service`;
  pico native launchd stack). A future `/onboard` must NOT "restore" them as an outage — the
  memory + this note say so explicitly. Re-enable only on explicit request.
- While the zig-computer server is off, the public site's `/client.zip` `/instances/` `/watchdog/`
  paths return 502 (they proxy the local watchdog `:5000`). Expected — the launcher client-download
  is down until the watchdog runs again.
- CDN is healthy but **empty** — publish flow gated on `vs-2f8.10` (PUBLISH_TOKEN) + `vs-2f8.11`.
- `ssh pico` (port 2222) is the ONLY path from zig-computer to pico; tailscale SSH is grammatically
  impossible. On headless pico use `launchctl bootstrap/bootout gui/501` (or `user/501`), never
  `brew services`.
- Prior handoff's DB-backup warning still stands (no confirmed backups since 2026-05-24 until
  vs-f6i lands) — do no risky DB work first.
