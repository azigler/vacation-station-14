# Upstream Sync

Vacation Station 14 is a curated SS14 derivative. This document lists
every upstream we track, our integration mode, and the cadence we
sync at. The per-cherry-pick workflow lives in
[`.claude/skills/upstream-sync/SKILL.md`](../.claude/skills/upstream-sync/SKILL.md).

## License boundary

AGPLv3 license boundary anchored at the Flavor A clear commit
`86a6f6a3bee0c6ac62c1dabfe6e38d79c6c00d2d` (2026-04-12). Content
contributed after that SHA is AGPLv3 unless explicitly annotated.
Inherited content keeps its original license — see the mode column
below.

## Tracked upstreams

| Remote | Upstream | Mode | License | Subdirectory | Cadence |
|---|---|---|---|---|---|
| `upstream-sw` | [space-wizards/space-station-14](https://github.com/space-wizards/space-station-14) | engine + base content | MIT | `Content.*` unprefixed, `RobustToolbox/` (submodule) | monthly re-checkout of selected files; engine submodule bumped with care |
| `upstream-dv` | [DeltaV-Station/Delta-v](https://github.com/DeltaV-Station/Delta-v) | cherry-pick | AGPL-3.0 + MIT (post-boundary split) | `_DV/` (Phase 5+) | ad-hoc per feature |

### Planned (Phase 5)

These rows are reserved for upstreams we expect to cherry-pick from.
Actual adoption is gated on Phase 4 curation output; rows move from
"planned" → "tracked" once the first cherry-pick from that upstream
lands.

| Remote | Upstream | Mode | License | Subdirectory |
|---|---|---|---|---|
| `upstream-nf` _(planned)_ | [new-frontiers-14/frontier-station-14](https://github.com/new-frontiers-14/frontier-station-14) | cherry-pick | AGPL-3.0 + MIT | `_NF/` |
| `upstream-ee` _(planned)_ | [Simple-Station/Einstein-Engines](https://github.com/Simple-Station/Einstein-Engines) | cherry-pick | AGPL-3.0 + MIT | `_EE/` |
| `upstream-starlight` _(planned)_ | [ss14Starlight/space-station-14](https://github.com/ss14Starlight/space-station-14) | cherry-pick | custom MIT-like | `_Starlight/` |
| `upstream-hardlight` _(planned)_ | [HardLightSector/HardLight](https://github.com/HardLightSector/HardLight) | cherry-pick | AGPL-3.0 + MIT | `_HardLight/` |

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
(SS14.Admin, SS14.MapServer, ss14-cookbook, Robust.Cdn, etc.) are
tracked in `external/` as git submodules, configured via `ops/`,
and not modified in place. See
[HOSTING.md](HOSTING.md) + [OPERATIONS.md](OPERATIONS.md).

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
