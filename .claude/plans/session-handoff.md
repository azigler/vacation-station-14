# Session handoff — 2026-05-04 (session 56c26bf8 cont., refreshed 2026-05-17)

## State at offboard

- **Current branch**: main
- **Last commit**: `76530ddb11` — `:wrench: ci: disable Publish Testing daily cron — PUBLISH_TOKEN unminted`
- **Open beads**: ~23 (5 ready, 0 in-progress, 4 deferred ❄)
- **In-flight subagents**: none
- **Dirty files**: none (clean working tree)
- **Markers**: no `.offboard-pending`
- **bv alerts**: 1/0/0/1 (info-only blocking_cascade — vs-ddu.5 unblocks 3 downstream; not actionable until Phase 4 runs)

## What happened this session

This session continued from `2026-05-02 (session 56c26bf8)` after compaction. Two phases of work:

**Phase A — Pre-compaction work** (carried over from earlier in 56c26bf8 per the compaction summary):
- vs-352, vs-lgs, vs-4ja, vs-kmz, vs-202, vs-1ya all closed
- CI workflow alignment (vs-kmz): 7 GH Actions workflows aligned to main + nightly cron + workflow_dispatch + main-PR + HTTPS-submodule rewrite
- Web events calendar Phase 1 shipped (vs-202): `/events`, iCal feed, `events.yml`. Phase 2 Discord-sync filed as vs-no1
- `nix run .#dev-services` now boots SS14 game-server itself via process-compose at `:1213` (vs-1ya), with port-collision avoidance + Content.Client ACZ prebuild
- vs-2f8.2 trigger-deferred and scope-expanded — nginx (not Caddy) + project-local /changelog skill extension + global /commit cross-ref + `.github/PULL_REQUEST_TEMPLATE.md` :cl: pre-fill + CONTRIBUTING.md "Changelog blocks" section + `docs/community/changelog.md` + end-to-end smoke-test example. Trigger fires on contributor PR / 2026-05-17 sweep / pre-launch / curation friction
- Wayfarer code-level recon — full walk of `Content.Server/_WF/CommunityGoals/` (16 files), 3 adoption strategies per feature, folded into vs-ddu.5 as Wayfarer-cell pre-work nucleus
- vs-i9u + vs-qd5 converted from defer → blocks-on vs-ddu.5 (Phase 4 dependency chain)
- vs-xvp.6 blocked-on vs-xvp (in-game Nurseshark feedback loop)

**Phase B — Post-compaction research-sweep** (this conversation's contribution):
- Read all 22 .md files in `~/research-ss14/` (the maintainer's separate private research repo)
- Mined the 2.6MB session transcript at `~/.claude/projects/-home-ubuntu-research-ss14/f5409d02-*.jsonl` via Explore agent for content NOT in the resulting docs
- Folded findings into 12 existing beads as `--notes` (vs-ddu, ddu.5, ddu.6, tks, 2l2, 17n, i9u, qd5, 2f8, 7ns closed, 3sh closed, kbs). Each note tagged `## Research-ss14 sweep — 2026-05-04` for grep
- Added vs-ddu.5 addendum on RMC-14 rejected-niche rationale + HRP-saturation-question scope for Phase 4 (per maintainer follow-up)
- Migrated `pwd.txt` secrets (postgres / watchdog ApiToken / grafana admin) from research-ss14/ into `.env.secrets` at repo root, gitignored at line 330. Treated as maintainer-local password manager
- Deleted `~/research-ss14/` after content was preserved (commits `fffa30c0af` + `df3007ba57`)
- Transcript JSONL at `~/.claude/projects/-home-ubuntu-research-ss14/f5409d02-*.jsonl` STAYS — bead notes reference it for any deeper future archaeology

**Phase C — Post-offboard follow-up** (2026-05-16, small touchup):
- Disabled the daily 10:00 UTC cron in `.github/workflows/publish-testing.yml` (commit `76530ddb11`). vs-2f8.1's re-enable was premature — `PUBLISH_TOKEN` is still unminted (vs-2f8.10 pending), so every nightly run since had been auth-failing. `workflow_dispatch` stays wired for manual smoke-testing
- vs-2f8.11 got a note: re-enabling the cron belongs in THAT bead's close-commit, after the manual workflow_dispatch run verifies end-to-end

## What's next

Three top picks for the next session, in order of leverage:

1. **vs-2f8.10 / vs-2f8.11** (CDN publish atomic human follow-ups) — bumped to top after cron disable. .10 is "mint PUBLISH_TOKEN + register GH Actions secret" (~10 min), .11 is "manual workflow_dispatch run end-to-end, then re-enable cron in publish-testing.yml in the same close-commit." Unblocks vs-17n AND restores nightly publishing.
2. **vs-tks** (Discord gating + age-verification interview) — `human:` prefix, but agentic prep work valuable: synthesize an interview script from the freshly-attached community-research notes, draft 6-8 questions for the maintainer to ask peers. Unblocks vs-2l2 → vs-z7v.
3. **vs-ddu.5** (Phase 4 ecosystem study) — `HUMAN — do not auto-execute`, but the orchestrator can pre-structure the per-upstream cells (DV/NF/RMC/HL/SL/CP/WF/EE/CX) using the now-attached research as starting nucleus. Single highest-leverage unlock (bv flagged it as blocking 3 downstream).

Lower-leverage agentic-only options: vs-1yd (Discord shield badge in README).

## Warnings / watch-outs

- **`.env.secrets` is now the local password manager.** `.gitignored` at root line 330. Contains 3 prod creds (postgres / watchdog ApiToken / grafana admin). If a credential rotates, update both the live config (per OPERATIONS.md rotation table) AND `.env.secrets` in the same change. **Never commit it.**
- **Don't reintroduce time leaks** in vs-tks Discord interview prep — vs14-voice rule: no specific cadences/cooldowns/audit windows in admin-side commitments.
- **vs-2f8.2 trigger-date is here.** The deferral named "2026-05-17 sweep" as one of three triggers — that date arrived. Don't auto-execute, but the next session should surface vs-2f8.2 to the maintainer for a fire-or-re-defer decision.
- **publish-testing cron is OFF** as of 2026-05-16. The schedule block is commented out in `.github/workflows/publish-testing.yml`; only `workflow_dispatch` is live. Re-enable belongs in vs-2f8.11's close-commit, AFTER PUBLISH_TOKEN mint (vs-2f8.10) and a verified manual workflow_dispatch run.
- **vs-i9u / vs-qd5 are blocks-on vs-ddu.5** — don't try to ship them ahead of Phase 4.
- **vs-xvp.6 is blocks-on vs-xvp** (maintainer's in-game Nurseshark feedback loop) — don't auto-execute.
- **bv alert is info-only** — vs-ddu.5 cascade is the structural bottleneck, not a hygiene problem. Clears when Phase 4 runs.
- **Research-ss14 folder is gone** — bead notes are now the canonical record. Transcript JSONL persists at `~/.claude/projects/-home-ubuntu-research-ss14/`; cite it from notes when deeper archaeology is needed.

---

## Infrastructure migration — zig-zone arc (2026-05-23 → 2026-05-24)

**This is not a vs14 work session.** Out-of-band, the operator + agent ran a multi-phase infra migration ("zig-zone") that significantly changed where vs14 services live. The vs14 code is unchanged; the deployment layout is dramatically different.

**Before you touch ops/, postgres, nginx, the docker-composes, or any service unit — read these references:**

- **Runbook** — `~/explore/.claude/skills/zig-zone/SKILL.md` (private). Topology, what runs where, ACL, recovery cheatsheet, 22 hard-won gotchas (#15–#22 are from this arc; #18 + #21 + #22 are vs14-specific).
- **Beads** — dotfiles repo, NOT vs14's beads:
  - `dotfiles-phe` — the zig-zone spec (3 scrutinize rounds; SHIPped)
  - `dotfiles-ozk` — Phase 2: Ollama + Phoenix → pico
  - `dotfiles-991` — Phase 3: postgres + vs14-web + obs containers + reef-router
  - `dotfiles-76s` — vs14-mapserver ARM64 native build (the `docker build --platform linux/arm64` fix)
  - `dotfiles-hdo` — Phase 4: SS14 + watchdog tried on pico, ROLLED BACK (canonical SS14 reverse-proxy architecture: don't UDP-proxy)
  - `dotfiles-ier` — research bead for the 0/30 counter bug (closed: was `admin.admins_count_in_playercount = false` default, not proxy-related)
  - `dotfiles-52c` — OPEN: future plan to move SS14 to pico via home-router DNAT
  - `dotfiles-q0c` — 7 of 8 vs14/ss14 timers ported to pico launchd

### What changed for vs14 deployment

| Service | Where it ran before | Where it runs now | Notes |
|---|---|---|---|
| **postgres@17** (vacation_station, vacation_station_mapserver) | zig-computer localhost:5432 | **pico** localhost:5432 + tailnet `pico.tailfb4637.ts.net:5432` (allowed from zig-computer's tailnet IP only via pg_hba) | DB migrated via `pg_dump -Fc` + `pg_restore`. SS14 game server on zig-computer now talks postgres over tailnet. |
| **vs14-web.service** (Next.js :3300) | zig-computer systemd | **pico** `~/Library/LaunchAgents/com.zig.vs14-web.plist` | Bound to pico tailnet IP; zig-computer nginx proxies → pico:3300. |
| **6 obs containers** (prometheus, loki, grafana, cdn, mapserver, ss14-admin) | zig-computer Docker | **pico** Colima Docker — all native ARM64 | mapserver + ss14-admin needed `docker build --platform linux/arm64 --no-cache` to produce real arm64 images (compose's default build silently picks amd64 even with DOCKER_DEFAULT_PLATFORM env — gotcha #18). |
| **Static dirs** /var/www/vs14-{recipes,guidebook,writer,maps} + external/nurseshark/dist | zig-computer disk | **pico** `/Users/pico/var/www/` + nurseshark dist on pico clone | nginx on pico (port 8080) serves the static paths; nginx on zig-computer proxies `/` → pico. |
| **Build/maintenance timers** (cookbook, guidebook, writer, nurseshark, map-render, ss14-backup, postgres-retention) — 7 of 8 | zig-computer systemd timers | **pico** launchd plists (installed by `~/dotfiles/vs14/install-timers.sh`) | Times stayed in PDT-equivalent of original UTC schedules. Build scripts work unchanged via `/opt/vacation-station → /Users/pico/vacation-station-14` symlink on pico. |
| **ss14-watchdog + Robust.Server + ss14-replay-rotate** | zig-computer | **STAYS on zig-computer** | Phase 4 SS14-on-pico attempted then rolled back. SS14's intrinsic source-IP-coupling (ban_address, GeoIP, ipintel_cache, admin logs) requires direct UDP delivery from the public IP. nginx UDP-proxying it = total loss of moderation. See dotfiles-52c for the future home-router DNAT path. |
| **reef-router** (granola webhook on :7575) | zig-computer | **pico** `~/Library/LaunchAgents/com.zig.reef-router.plist` | zig-computer nginx adds a `listen 7575` server block that proxies to pico. Granola webhook URL unchanged externally. |

### Two clones of `vacation-station-14`

The git tree is now cloned in TWO places that can drift:

- **zig-computer**: `/home/ubuntu/vacation-station-14` (this repo). Touched at: `.env.secrets` (live), `/opt/ss14-watchdog/instances/vacation-station/config.toml` (live, NOT in this tree — it's a separate watchdog instance config).
- **pico**: `/Users/pico/vacation-station-14`. Touched at: docker-compose.override.yml files in ops/ss14-admin/ + ops/observability/ (gitignored), patched appsettings.yml urls (ss14-admin), built static dirs (cookbook/guidebook/writer/nurseshark output now goes to pico's /Users/pico/var/www/).

**When you `git pull` here, also pull on pico** for any change that touches `ops/*/build.sh`, `external/*` submodules used by build pipelines, or web/ — otherwise the timers + vs14-web will be running stale. SSH: `tailscale ssh pico@pico "cd /Users/pico/vacation-station-14 && git pull && git submodule update"`.

### vs14-specific gotchas captured in the zig-zone runbook

- **#18** — `docker-compose build` silently picks amd64 on Apple Silicon. Use bare `docker build --platform linux/arm64 --no-cache` for mapserver / ss14-admin rebuilds.
- **#19** — macOS Homebrew nginx as `nobody` can't traverse `/Users/<user>/` (mode 700). Set `user pico staff;` at top of nginx.conf.
- **#20** — macOS Colima can't bind ports to the macOS host's tailnet IP directly. Use `0.0.0.0:PORT:PORT` + container-internal 0.0.0.0 bind.
- **#21** — ASP.NET Core appsettings.yml `urls:` overrides `ASPNETCORE_URLS`. For ss14-admin we patched `urls: "http://0.0.0.0:5427/"` on pico's clone.
- **#22** — SS14 hides admins from `/status` players count by default. We applied `[admin] admins_count_in_playercount = true` to the live `/opt/ss14-watchdog/instances/vacation-station/config.toml` on zig-computer. **Consider whether the source `Resources/ConfigPresets/Build/development.toml` or whichever default config template should also carry this** — currently it's a live-edit only.

### Open vs14-impacting items in dotfiles beads (not vs14's beads)

- `dotfiles-52c` (P3) — future SS14 → pico via home-router DNAT + DDNS. Build artifacts already on pico awaiting this. Read for the alternatives matrix (PROXY protocol, TPROXY) if you're ever curious whether there's a simpler path.
- `dotfiles-st2` (P3) — iPhone Termius shows broken nerdfont glyphs via Tailscale SSH; workaround = connect to public IP. Doesn't affect anything vs14 except admin-from-phone.

If you're picking up vs14 work — none of this BLOCKS your work, just don't be surprised when `systemctl status vs14-web` says inactive on zig-computer, or `psql vacation_station` from zig-computer prompts for password (it now goes over tailnet to pico).
