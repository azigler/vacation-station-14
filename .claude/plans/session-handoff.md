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
