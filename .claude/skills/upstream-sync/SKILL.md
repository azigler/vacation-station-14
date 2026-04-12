---
description: Sync from tracked upstreams — engine submodule bumps, SS14 base content refreshes, sibling-fork cherry-picks
---

# Upstream Sync

Vacation Station 14 is a curated SS14 derivative. There is no single
"the" upstream; we track several, each with its own integration mode.
The canonical list lives at [`docs/upstream-sync.md`](../../docs/upstream-sync.md).

## Prerequisites

Confirm the expected remotes exist:

```bash
git remote -v
```

Expected (post-Flavor-A):
- `origin` → azigler/vacation-station-14
- `upstream-sw` → space-wizards/space-station-14
- `upstream-dv` → DeltaV-Station/Delta-v
- `upstream-nf`, `upstream-ee`, … added per Phase 5 curation

If missing: `git remote add upstream-<name> <repo>` then
`git fetch upstream-<name>`.

## Mode 1 — engine submodule bump (upstream-sw / RobustToolbox)

```bash
cd RobustToolbox
git fetch origin
git log --oneline origin/master -10        # review incoming
git checkout <new-sha>
cd ..
git add RobustToolbox
dotnet build                                # must stay green
git commit -m ":arrow_up: engine: bump RobustToolbox to <ver> (<sha>)"
git push
```

The pre-commit hook BLOCKS staged RobustToolbox changes by default.
Engine bumps need the temporary hook workaround — see the pattern
documented in `vs-ddu.2` (Phase 1 commit).

## Mode 2 — SS14 base content refresh (upstream-sw, unprefixed Content.*)

Base content updates are scoped checkouts, never a blanket merge.
Pick the specific files + directories to refresh; review the diff;
commit.

```bash
git fetch upstream-sw
git checkout upstream-sw/master -- Content.Shared/Administration/
dotnet build && dotnet test Content.Tests --no-build
git diff --cached --stat                   # review
git commit -m ":arrow_up: ss14: refresh Content.Shared/Administration from upstream-sw"
git push
```

Why scoped, not merged: we intentionally don't want every SS14 master
update — that would re-introduce content we're still curating under
Phase 4. Scoped refresh lets us pull in specific bugfixes, security
patches, or subsystems without a tide of unrelated churn.

## Mode 3 — cherry-pick from a sibling fork (upstream-dv, upstream-nf, …)

The most common and most discipline-heavy mode.

```bash
git fetch upstream-<fork>
git log --oneline upstream-<fork>/master --grep="<feature>" -10

# Cherry-pick with author preservation
git cherry-pick -x <upstream-sha>

# If conflicts: resolve keeping _VS edits, preserving upstream intent
# in the conflicted _<fork>/ code. Add `// <FORK> - ...` annotations
# on any line we modified during resolution.

dotnet build && dotnet test Content.Tests --no-build

# Amend the commit to add bead trailer + subsystem tag
git commit --amend -m "$(cat <<EOF
cherry-pick: _<FORK>/<feature> from <fork-name>@<short-sha>

Upstream: <upstream-sha>
<one-paragraph description of the feature>

Bead: vs-xyz
Co-Authored-By: <original-author>
EOF
)"
git push
```

Discipline:
- Use `git cherry-pick -x` so the generated commit body includes
  the upstream SHA automatically.
- Preserve the original `Author:` line (cherry-pick does this by
  default).
- Add `Co-Authored-By:` for the original author if our resolution
  materially edited the code.
- Tag the subsystem in the subject: `cherry-pick: _NF/Bank from …`
- Always reference the VS14 bead scoping the pick.
- Never squash cherry-picks — license chain depends on individual
  SHA-level traceability.

## Conflict bias

| Hunk | Bias |
|---|---|
| `_VS/` file | keep ours (our code) |
| `_<FORK>/` file we're cherry-picking INTO | respect upstream intent; add `// <FORK> - ...` for any resolution edits |
| Unprefixed `Content.*` | re-apply our `// VS` annotations on top of upstream changes |
| `RobustToolbox/` submodule | never modified by cherry-picks |
| `.github/` workflows | keep ours unless we're pulling an upstream's workflow deliberately |

## Mode 4 — deploy-as-is service refresh

Third-party services (SS14.Admin, SS14.MapServer, ss14-cookbook, etc.)
are tracked as submodules under `external/`. Refresh = bump the
submodule SHA, re-deploy.

```bash
cd external/<service>
git fetch origin
git checkout <new-sha>
cd ../..
git add external/<service>
git commit -m ":arrow_up: deps: bump external/<service> to <ver>"
git push
# Deploy update per docs/OPERATIONS.md for that service
```

## Verification after any sync

```bash
dotnet build --configuration DebugOpt
dotnet test Content.Tests --no-build --configuration DebugOpt
dotnet test Content.IntegrationTests --no-build --configuration DebugOpt
dotnet run --project Content.YAMLLinter
```

A broken baseline is worse than a stale baseline — never push a sync
commit that red-lines the build.

## Cadence

See [`docs/upstream-sync.md`](../../docs/upstream-sync.md) for the
per-upstream table — each row lists its own cadence. There is no
global sync schedule.

## When to escalate to a bead

Any cherry-pick that touches:
- A cross-cutting system (jobs, roles, map loading, auth)
- > 50 files
- An upstream we haven't cherry-picked from before

…gets its own bead (`br create -p 2 "cherry-pick: _NF/Bank"`) with
the curation context captured in the description. Simple 1-2 file
feature-level picks can skip this and go straight into a commit.
