# Upstream Sync

Vacation Station 14 is a curated SS14 derivative. This document lists
every upstream we track, our integration mode, and the cadence we
sync at. The per-cherry-pick workflow lives in
[`.claude/skills/upstream-sync/SKILL.md`](../.claude/skills/upstream-sync/SKILL.md).

## License boundary

AGPLv3 license boundary anchored at the Flavor A clear commit
`86a6f6a3bee0c6ac62c1dabfe6e38d79c6c00d2d` (2026-04-12), tagged
permanently as `flavor-a-baseline-2026-04-12`. Content contributed
after that SHA is AGPLv3 unless explicitly annotated. Inherited
content keeps its original license — see the mode column below.

The pre-reset state is preserved at the `pre-flavor-a-clear` tag
for historical / license-chain purposes.

## Tracked upstreams — git remotes

| Remote | Upstream | Mode | License | Subdirectory | Cadence |
|---|---|---|---|---|---|
| `upstream-sw` | [space-wizards/space-station-14](https://github.com/space-wizards/space-station-14) | engine + base content | MIT | `Content.*` unprefixed, `RobustToolbox/` (submodule) | monthly re-checkout of selected files; engine submodule bumped with care |
| `upstream-dv` | [DeltaV-Station/Delta-v](https://github.com/DeltaV-Station/Delta-v) | cherry-pick | AGPL-3.0 + MIT (post-boundary split) | `_DV/` (Phase 5+) | ad-hoc per feature |
| `upstream-nf` | [new-frontiers-14/frontier-station-14](https://github.com/new-frontiers-14/frontier-station-14) | cherry-pick | AGPL-3.0 + MIT (post-boundary split) | `_NF/` (Phase 5+) | ad-hoc per feature |
| `upstream-rmc` | [RMC-14/RMC-14](https://github.com/RMC-14/RMC-14) | cherry-pick | AGPL-3.0 + MIT | `_RMC/` (Phase 5+) | ad-hoc — Aliens-mode / combat / scenario content |
| `upstream-hl` | [HardLightSector/HardLight](https://github.com/HardLightSector/HardLight) | cherry-pick (meta-aggregator) | AGPL-3.0 + MIT | `_HL/` (Phase 5+) | ad-hoc — dense source, already aggregates ~20 other forks |
| `upstream-sl` | [ss14Starlight/space-station-14](https://github.com/ss14Starlight/space-station-14) | cherry-pick | MIT (+ modified-MIT middle period, see LEGAL.md) | `_SL/` (Phase 5+) | ad-hoc — structured-RP tone reference; default branch `starlight-dev` |
| `upstream-cp` | [crystallpunk-14/crystall-punk-14](https://github.com/crystallpunk-14/crystall-punk-14) | cherry-pick | MIT | `_CP/` (Phase 5+) | ad-hoc — fantasy/magic-RP co-op reframing of SS14; unique thematic niche |

## Tracked upstreams — deploy-as-is submodules (bundled services)

Per the decision matrix in **vs-19h**. LICENSE files retained inside
each submodule directory, automatically satisfying MIT attribution +
AGPL notice-retention requirements.

| Path | Upstream | License | Config dir | Landed via |
|---|---|---|---|---|
| `external/cookbook/` | [arimah/ss14-cookbook](https://github.com/arimah/ss14-cookbook) | AGPL-3.0 | `ops/cookbook/` | vs-1vy |
| `external/mapviewer/` | [space-wizards/SS14.MapViewer](https://github.com/space-wizards/SS14.MapViewer) | MIT | `ops/mapviewer/` | vs-236 |
| `external/mapserver/` | [space-wizards/SS14.MapServer](https://github.com/space-wizards/SS14.MapServer) | MIT | `ops/mapserver/` (container image reused by `ops/map-render/`) | vs-2nk |
| `external/document-simu/` | [yagwog/RMC14-document-simu](https://github.com/yagwog/RMC14-document-simu) | MIT | `ops/document-simu/` | vs-v69 |
| `external/ss14-admin/` | [space-wizards/SS14.Admin](https://github.com/space-wizards/SS14.Admin) | MIT | `ops/ss14-admin/` | vs-35d |

## Not yet added as remotes (candidates)

Adding a remote is free; we add one when we expect imminent curation
work from that fork. Current candidates:

| Upstream | Why worth tracking eventually |
|---|---|
| [Simple-Station/Einstein-Engines](https://github.com/Simple-Station/Einstein-Engines) | future `_EE/` — modular upstream for Nyanotrasen-lineage servers; democratic governance |
| [space-syndicate/space-station-14](https://github.com/space-syndicate/space-station-14) | future `_CX/` — Corvax, primary RU-speaking fork |

Nyanotrasen is **not** tracked — the project is dormant and its
feature set has been absorbed into active forks (psionics → Einstein
Engines, mail job → Delta-V, Felinids/Moths/Arachne →
Parkstation/Simple-Station). Pull those features from their active
carriers rather than from the original Nyanotrasen repo.

## Integration modes

**engine** — RobustToolbox is pinned as a git submodule. Engine
versions bump explicitly via `cd RobustToolbox && git checkout
<sha> && git add RobustToolbox` in a dedicated commit.

**base content** — SS14's `Content.*` (unprefixed) came in via the
Flavor A Phase 1 `git checkout upstream-sw/master -- Content.*`.
Future pure-SS14 content updates come in the same way, scoped to
specific files — never a blanket merge.

**cherry-pick** — features from sibling forks land inside
`_<FORK>/` subsystems, one commit per logical feature, preserving
the upstream author. Conflict resolution keeps our `_VS/` edits
and respects the upstream author's intent.

**deploy-as-is** — third-party services bundled alongside the game
(SS14.Admin, SS14.MapServer, SS14.MapViewer, ss14-cookbook,
Robust.Cdn, etc.) are tracked in `external/` as git submodules,
configured via `ops/`, and not modified in place. See the full
table above, plus [HOSTING.md](HOSTING.md) + [OPERATIONS.md](OPERATIONS.md).
Once we fork a service (modify it), the directory migrates from
`external/<name>/` → `services/<name>/` per the policy in
[`CONTRIBUTING.md`](../CONTRIBUTING.md#bundled-services).

## Adding a new upstream

1. Add the remote:
   `git remote add upstream-<name> <repo-url> && git fetch upstream-<name>`
2. Decide the subdirectory prefix (`_NF`, `_EE`, ...). Convention:
   match the upstream's own name when it's already established in
   the SS14 community; otherwise coordinate via a bead.
3. Add a row to this file + README.md's attribution table in the
   same commit that introduces the first cherry-pick.
4. Follow the cherry-pick workflow in
   [`.claude/skills/upstream-sync/SKILL.md`](../.claude/skills/upstream-sync/SKILL.md).

## Removing an upstream

If an upstream is abandoned, archived, or otherwise unsuitable for
continued cherry-picking:

1. File a bead scoping the consequences. Do we preserve existing
   cherry-picked code in `_<FORK>/`? Re-author under `_VS/` with
   attribution preserved in the commit history?
2. Remove the remote + update this file + README.
3. Keep the historical attribution intact in git history. Never
   rewrite history to erase an upstream.
