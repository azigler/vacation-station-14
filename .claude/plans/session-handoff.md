# Session handoff — 2026-05-26 (session 76d779b6, covers 2026-05-23 prod-triage + 2026-05-25 CI-flake-fix)

## State at offboard

- **Current branch**: main
- **Last commit**: `59ca38a116` — `:card_file_box: beads: close vs-4h1.1`
- **Open beads**: ~27 (1 P1 epic, 11 P2, 14 P3; 1 in-progress: vs-4h1; 4 deferred ❄)
- **In-flight subagents**: none
- **Dirty files**: none after offboard commit
- **Markers**: `.offboard-pending` cleared by this offboard

## What happened this session

This handoff covers two phases that bracket a session-resume — the prior session ended without offboard (left `.offboard-pending`), and this resume took on a new task. Both phases are captured here as one bracket.

### Phase A — 2026-05-23 prod triage (pre-resume)
- **Fixed SS14 launcher 502** — `vs14-cdn` container had been silently exited for 4 weeks (since 2026-04-19). Root cause: `ops/cdn/` → `ops/robust-cdn/` rename during vs-2f8.1 updated the compose mount path but the live container was never recreated; on next restart docker's bind-mount of the (now missing) old path auto-created an empty *directory*, poisoning every subsequent start. Recreated container via `docker compose up -d cdn`; both `/cdn/.../manifest` and `/cdn/.../SS14.Client.zip` return 200. vs-2f8.1 was prematurely closed as "service live"; reality was outage. Discovered only when maintainer tried the launcher.
- **Cleaned up stale `ops/cdn/`** debris dirs (root-owned, empty, both in `/opt/` and `/home/` clones).
- **Fixed admin permissions** — `spacezig` had Host rank with only the `HOST` flag (despite the name, `HOST` is just one flag among 23 — not a superflag). Granted all 22 missing flags via SQL direct on the `vacation_station` postgres DB. Reconnect required to refresh the cached perms.
- **Expanded vs-2f8.8** (blackbox monitoring bead) to include vs14-cdn + admin + mapserver + game-server status port — incident attached as evidence. Bead stays deferred (P3) per maintainer.
- **Updated memory** — `project_publishing.md` now captures the silent-failure pattern (post-rename container, no monitoring).

### Phase B — 2026-05-25 CI flake fix (this resume)
- **Diagnosed Build & Test Debug failure** (run 26388756804). `Ss14WrapperRemoteAddressOverrideTests.LookupViaSocket_ConcurrentInvocations_NoCrossContamination` flaked with 4/10 `SocketException: Connection timed out`. 200ms `ReceiveTimeout` insufficient under 10-way Parallel.For on GH 2-vCPU shared runner. Not a production bug — real wrapper is co-located + sub-ms.
- **Fixed** (vs-4h1.1, commit `c4ae0d1d90`): added optional `int timeoutMs = ReadTimeoutMs` parameter to `LookupViaSocket` (additive on already-`internal static` test seam); concurrent test now passes `timeoutMs: 5000`. Production default stays 200ms; `_SocketTimeout_Throws` still verifies the production timeout.
- **Verified**: 4 consecutive local runs of `Ss14WrapperRemoteAddressOverrideTests` 15/15 each (344-459ms); dispatched CI run 26405020115 → ✓ success in 14m57s.
- **Cleaned**: stray `.claude/worktrees/agent-a54bcfc4047afa256` from a cancelled dispatch (worktree hook returned cancel but actually created the worktree; manually removed + branch deleted).

## What's next

Three top picks, in order of leverage:

1. **vs-4h1 parent close** (◐ in_progress) — vs-4h1.1 closed the CI flake; check whether the broader ss14-c2 IRemoteAddressOverride bead has any remaining acceptance gaps before closing the parent. Look at vs-q7m (scrutiny SHIP) which was the prior wave.
2. **vs-2f8.10 / vs-2f8.11** (CDN publish atomic human follow-ups) — still pending. .10 is "mint PUBLISH_TOKEN + register GH Actions secret" (~10 min), .11 is "manual workflow_dispatch run end-to-end, then re-enable cron in publish-testing.yml in the same close-commit." Unblocks vs-17n AND restores nightly publishing.
3. **vs-2f8.8 re-thaw decision** — blackbox monitoring bead, now scoped to include vs14-cdn after the 4-week silent outage incident. Stays deferred until 2026-07-02 per current `defer:` field, but the incident is strong evidence for earlier re-thaw. Maintainer call.

Lower-leverage agentic-only options: vs-tks (Discord gating interview prep), vs-ddu.5 cell pre-structuring, vs-1yd (Discord shield badge).

## Warnings / watch-outs

- **`.env.secrets` is the local password manager.** `.gitignored` at root line 330. Contains 3 prod creds (postgres / watchdog ApiToken / grafana admin). If a credential rotates, update both live config AND `.env.secrets` in the same change. **Never commit it.**
- **`ops/cdn/` is FORBIDDEN as a path.** Docker bind-mount creates empty directories there on missing-source restart, and that pattern just cost us a 4-week silent CDN outage. Always use `ops/robust-cdn/`. Memory `project_publishing.md` captures the failure shape.
- **publish-testing cron is OFF** as of 2026-05-16. Schedule block commented in `.github/workflows/publish-testing.yml`; only `workflow_dispatch` is live. Re-enable belongs in vs-2f8.11's close-commit, AFTER PUBLISH_TOKEN mint (vs-2f8.10) and a verified manual workflow_dispatch run.
- **vs-i9u / vs-qd5 are blocks-on vs-ddu.5** — don't try to ship them ahead of Phase 4.
- **vs-xvp.6 is blocks-on vs-xvp** (maintainer's in-game Nurseshark feedback loop) — don't auto-execute.
- **The worktree-create hook can cancel mid-dispatch but still create the worktree.** If a dispatch fails with "Hook cancelled," check `git worktree list` and clean up before continuing — don't assume the worktree wasn't created. (Saw this on the vs-4h1.1 dispatch attempt 2026-05-25.)
- **No blackbox monitoring still.** vs14-cdn, admin, mapserver, nurseshark, cookbook, guidebook are all subject to the same silent-failure shape that bit us 2026-04-19 → 2026-05-23. Anything proxied by nginx → docker can die invisibly. vs-2f8.8 covers this; until thawed, treat any "service quietly stopped working" report as plausibly weeks old.
