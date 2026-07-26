# vs14 — upstream drift & catch-up assessment

**Date:** 2026-07-26 · **Bead:** explore-9ct8 · **Branch:** `vs14-upstream`
**Every number below is `[measured]` unless marked `[inferred]`.**

---

## TL;DR

vs14 is **879 commits / 104 days behind** space-wizards/space-station-14, and its
engine is **289 commits / 9 major versions** behind RobustToolbox. That sounds
dire. It isn't.

**The catch-up was performed, resolved, and built green in this session.** Real
conflict count: **10 files** — of which **one** is C# source and **eight** are
CI/nix/meta. The full solution then compiled with **0 errors** after a
**3-line** fix to a single file.

The reason it's cheap: vs14 barely diverged. Of 274 changed paths, **246 are
pure additions** (ops/, web/, docs/, harness) that cannot conflict, and only
**3 are C# files**. vs14 is "stock SS14 + an ops harness + one networking
patch," not a content fork.

**The one strategic disappointment is §7:** upstream's automation surface is
*flat*. The HTTP admin API is byte-for-byte functionally unchanged across all
879 commits. Tracking upstream neither helps nor hurts the agentic plan — vs14d
will have to build that layer itself.

---

## 1. Upstream identity

`.gitmodules` and the remote list are misleading — there are **nine** `upstream-*`
remotes (crystallpunk, DeltaV, HardLight, Frontier, RMC-14, Starlight, wizards,
wayfarer). Only one is live.

The root commit says *"hard fork of Delta-V Station at a3e9436c"*, but that
lineage was **superseded**. `FORK_POINT` (repo root) records the truth:

```
Vacation Station 14 — Flavor A architectural reset
Phase 1 clear commit: 86a6f6a3bee0c6ac62c1dabfe6e38d79c6c00d2d
Baseline tag: flavor-a-baseline-2026-04-12
Base: space-wizards/space-station-14 @ upstream-sw/master
RobustToolbox pin: 3136118b5338ef2d9580178caf5c723e65eb76e7 (Version: 275.2.0)
Prior lineage (pre-Flavor-A, superseded):
- Delta-V Station fork point a3e9436c... (2026-04-11)
```

| Role | Repo | URL |
|---|---|---|
| **Content upstream (live)** | `space-wizards/space-station-14` | https://github.com/space-wizards/space-station-14 |
| **Engine upstream (live)** | `space-wizards/RobustToolbox` | https://github.com/space-wizards/RobustToolbox |
| Engine fork vs14 pins | `azigler/RobustToolbox` | https://github.com/azigler/RobustToolbox |
| Superseded ancestor | `DeltaV-Station/Delta-v` | https://github.com/DeltaV-Station/Delta-v |

Commit `86a6f6a3` (2026-04-12, *":boom: reset: clear Delta-V-inherited content;
rebase on pure SS14"*) cleared Delta-V content and re-baselined on stock SS14.
**Delta-V and the other seven remotes are dead weight** — safe to delete.

### The structural fact that shapes everything

```
git merge-base HEAD upstream-sw/master   →  exit 1, no output
git merge-base HEAD upstream-dv/master   →  exit 1, no output
```

**vs14 has ZERO shared git ancestry with any upstream.** One root commit
(`062c0d7a`, 2026-04-11); 380 commits total; the fork imported a *working tree*,
not history. So `git merge upstream-sw/master` gives *"refusing to merge
unrelated histories,"* and `--allow-unrelated-histories` would use the empty
tree as base and conflict on essentially every file. Neither is the real cost —
they're artifacts of the missing ancestry.

**The fix:** the fork point is *recoverable by content*. Diffing the baseline tag
against upstream commits by tree, the minimum is **3 files** at:

> **`825671c3b092283f689bddd457bec0b31f76350e`** — 2026-04-12 19:16 UTC,
> *"Automatic changelog update"*

That commit is the true merge base, and supplying it explicitly
(`git merge-tree --merge-base=`) turns an impossible merge into a 10-conflict one.

---

## 2. Content drift

| Metric | Value |
|---|---|
| Fork point | `825671c3` — 2026-04-12 |
| Upstream HEAD at measurement | `b92ce00026` — 2026-07-25 (*"Bugfix: Check UIDs in TryMergeStacks (#44914)"*) |
| **Commits behind** | **879** |
| **Time span** | **104 days** (2026-04-12 → 2026-07-25) |
| Upstream files changed in that window | 5,480 |
| Upstream cadence | Apr 267 · May 230 · Jun 174 · Jul 330 /mo |

### vs14's own divergence — the real cost driver

`git diff --name-status 825671c3 HEAD` → **274 paths**:

| Status | Count | Meaning |
|---|---|---|
| **A** (added) | **246** | new files — **cannot conflict** |
| **M** (modified) | **28** | the only overlap risk |
| **D** (deleted) | **0** | nothing removed from upstream |

The 246 additions by area: `ops/` 82, `web/` 42, `docs/` 24, `assets/` 21,
`Resources/` 12, `.claude/` 10, `hooks/` 9, `.github/` 8, rest scattered.

**Only 3 of the 246 additions are C# files** — all one feature:
```
Content.Server/Connection/Ss14WrapperRemoteAddressOverride.cs
Content.Tests/Connection/Ss14WrapperCvarTests.cs
Content.Tests/Connection/Ss14WrapperRemoteAddressOverrideTests.cs
```

Of the **28 modified** files, **19 were also touched upstream**. But only
**3 are substantive source/content**:

| File | Local delta | Nature |
|---|---|---|
| `Content.Server/IoC/ServerContentIoC.cs` | +7 | wrapper IoC registration |
| `Content.IntegrationTests/.../LogWindowTest.cs` | 29 | CI-flake timing fix |
| `Resources/ServerInfo/Guidebook/Medical/MedicalDoctor.xml` | 4 | content tweak |
| `flake.nix` / `shell.nix` | +496 / +52 | Zig's nix dev env |
| `.github/workflows/*` (11) · `.gitignore` · `flake.lock` | — | CI (disabled) + meta |

> **Sibling-agent dependency:** the `vs14-assess` agent is cataloguing *what*
> Zig's work is. This doc establishes only its *shape*: 246 additive files
> (ops/web/docs harness) + 3 C# files + a nix env. That shape is what makes the
> merge cheap, and it holds regardless of how the content is valued.

---

## 3. Submodule drift

**Only RobustToolbox has meaningful drift. Everything else is at or near parity.**

| Submodule | Local | Upstream | Behind | Ahead |
|---|---|---|---|---|
| **RobustToolbox** | `85982545e` v275.2.0+2 | `3149158d` **v285.0.0** | **289** | **2** |
| `external/ss14-admin` | `b5ab8606` v1.9.1 | `b5ab8606` | **0** | 0 |
| `external/robust-cdn` | `0b2b814e` v2.2.0-3 | `0b2b814e` | **0** | 0 |
| `external/mapviewer` | `e48f0a76` | `e48f0a76` | **0** | 0 |
| `external/mapserver` | `8f2362b3` | `fc0d07ae` | 2 | 0 |
| `external/document-simu` | `6757e6eb` | `cb4c2252` | 2 | 0 |
| `external/cookbook` | `f4b733e1` | `2d24f78e` | 7 | 0 |
| `external/nurseshark` | `1472e376` | (azigler's own) | — | — |

**`ss14-admin` is 0 behind because upstream itself is stale** — SS14.Admin's last
commit is 2026-01-23 (*"How did this dockerfile ever work?"*), 6 months cold.
`[inferred]` The admin web UI is not an area Wizden is investing in; do not plan
vs14d's control plane around it.

**Latent bug found:** `.gitmodules` declares `branch = main` for `external/cookbook`
and `external/mapviewer`, but **both repos' actual default branch is `master`**.
`git submodule update --remote` fails on both (`fatal: couldn't find remote ref main`).
One-line fix each.

### Engine ⇄ content version constraint — this is the real coupling

| | Engine version |
|---|---|
| vs14 content pins | **275.2.0** (+2 local commits) |
| **upstream-sw/master pins** (`2c5cd424`) | **284.0.0** |
| RobustToolbox master HEAD | 285.0.0 |

SS14 majors mean breaking changes; **275 → 284 is nine of them**. Content and
engine **must move as a matched pair** — catching content up to
`upstream-sw/master` without taking engine 284 will not build. Correspondingly,
do *not* jump the engine to 285: upstream content hasn't adopted it
(285 changes XAML `StyleClasses` syntax). **Target 284.0.0, i.e. exactly the
commit upstream content pins.**

Breaking changes across the window (from `RELEASE-NOTES.md`):
- **276** — obsolete `MapGridComponent` methods removed
- **277** — **`[Dependency]` source generator**: dependency-holding types must be
  `partial` and fields non-`readonly`. *"not yet an error, but will become one"* —
  currently analyzer-level (`RA0049` / `RA0051`). **This is the only thing that
  broke vs14's build.**
- **278** — `ComponentRegistryEntry` serialization copy removed; `LocalRotation`,
  `IMapManager` obsoleted
- **279** — `QuadTree` removed; `SpawnAtPosition` rotation semantics changed;
  `Box2i` validation; `ReallyBeIdle` 25 → 5
- **280** — **`IMapManager` completely removed** (ported to `SharedMapSystem`)
- **285** — XamlX `StyleClasses` syntax change *(avoid — beyond content's pin)*

`[measured]` **None of these touch vs14's own code.** Zig's 3 C# files are
networking-only; the map/serialization/XAML breakage lands entirely on upstream
content, which upstream already fixed for us.

---

## 4. Recommended merge path

> ### Verdict: **re-baseline onto upstream, keeping vs14's history — do NOT rebase, do NOT restart.**
> Take upstream's tree wholesale and re-apply vs14's additive layer on top,
> because 246 of 274 changed paths are pure additions that never conflict and only
> 3 C# files carry real logic — so upstream's version of everything else is
> strictly better than a hand-merged hybrid. Rebase is the wrong tool outright:
> with no shared ancestry there is nothing to rebase *onto*, and replaying 380
> commits whose first commit *is* the entire fork import would conflict on
> essentially every file for zero benefit.

The mechanism is the merge-base trick, which makes this a routine merge:

```bash
# 1. engine: real ancestry exists, plain merge works, ZERO conflicts
cd RobustToolbox && git merge 2c5cd424167aad2997c448e5cd1ab2d9d0eea8c8   # v284.0.0

# 2. content: supply the recovered fork point as an explicit base
git merge-tree --write-tree \
  --merge-base=825671c3b092283f689bddd457bec0b31f76350e \
  HEAD upstream-sw/master
```

**Alternatives weighed:**
- *`--allow-unrelated-histories` merge* — rejected: empty-tree base ⇒ thousands of
  spurious conflicts. The 10-conflict number only appears with the correct base.
- *`git replace --graft` to synthesize ancestry* — genuinely tempting and it would
  make future merges native. **Rejected here for a safety reason:** `refs/replace`
  is repo-wide and shared across worktrees, so it would have altered commit
  reading for the concurrently-running `vs14-assess` agent. `[inferred]` It is
  the right *permanent* fix, applied deliberately when no sibling agent is live.
- *Fresh clone + re-apply* — same end state as the recommendation but discards
  vs14's 380 commits of ops/incident history for no gain.

**Permanent fix worth doing once:** graft the ancestry (`git replace --graft`, then
`git filter-repo` to make it durable) so every *future* catch-up is a plain
`git merge` with no special flags.

---

## 5. Dry run — what actually conflicted

Performed in this worktree with `git merge-tree` (in-memory; no ref/worktree
mutation), base `825671c3`, `HEAD` ← `upstream-sw/master`.

### Content: **10 conflicted paths**

| # | Path | Kind | Resolution taken |
|---|---|---|---|
| 1 | `Content.IntegrationTests/.../LogWindowTest.cs` | **C# source** | upstream *(re-apply flake fix later)* |
| 2 | `RobustToolbox` | **submodule** | merged engine commit |
| 3 | `.gitignore` | meta | ours |
| 4 | `flake.nix` | nix env | ours |
| 5 | `flake.lock` | nix env | ours |
| 6 | `.github/PULL_REQUEST_TEMPLATE.md` | CI | upstream |
| 7–10 | `.github/workflows/{validate-rgas,validate-rsis,validate_mapfiles,yaml-linter}.yml` | CI | upstream |

**Auto-merged cleanly** (worth naming — these are the ones that mattered):
- `Content.Server/IoC/ServerContentIoC.cs` — **the wrapper IoC hook survived untouched**
- `Resources/ServerInfo/Guidebook/Medical/MedicalDoctor.xml`
- `shell.nix`, and 7 further `.github/workflows/*`

Post-resolution: `git grep '^<<<<<<< '` → **no leftover markers**.

### Engine: **0 conflicts**

```
git merge-tree --write-tree --merge-base=3136118b HEAD 2c5cd424  →  exit 0
```

A plain `git merge` then succeeded with no conflicts. **Zig's `IRemoteAddressOverride`
patch survived intact** across 289 commits and 9 major versions — verified: 8
references in `NetManager.cs`, 1 in `NetManager.ServerAuth.cs`, interface file
present, engine reports `<Version>284.0.0</Version>`.

Why it was free: of the 9 engine files vs14 touches, 5 are **new files** (0
upstream commits) and only 3 overlap (`CVars.cs` 9 commits, `NetManager.cs` 6,
`NetManager.ServerAuth.cs` 3) — all additive hunks in different regions.

---

## 6. Does it build? **Yes.**

`dotnet` 10.0.109 vs `global.json` 10.0.100 `rollForward: latestFeature` — OK.

**Attempt 1 — `dotnet build Content.Server -c Release`: FAILED, exactly 3 errors,
all in one file, all the RTB-277 DI migration:**

```
Content.Server/Connection/Ss14WrapperRemoteAddressOverride.cs(53,19): error RA0049:
  Type 'Content.Server.Connection.Ss14WrapperRemoteAddressOverride' has [Dependency]
  fields but is not partial. This will be required in the future.
Content.Server/Connection/Ss14WrapperRemoteAddressOverride.cs(70,30): error RA0051:
  Field '_cfg' is a [Dependency] but is readonly. This will be an error in the future.
Content.Server/Connection/Ss14WrapperRemoteAddressOverride.cs(71,30): error RA0051:
  Field '_logMan' is a [Dependency] but is readonly. This will be an error in the future.
```

**The fix — 3 lines**, exactly the mechanical migration upstream already did to
its own code:
```diff
-    public sealed class Ss14WrapperRemoteAddressOverride : IRemoteAddressOverride
+    public sealed partial class Ss14WrapperRemoteAddressOverride : IRemoteAddressOverride
-        [Dependency] private readonly IConfigurationManager _cfg = default!;
-        [Dependency] private readonly ILogManager _logMan = default!;
+        [Dependency] private IConfigurationManager _cfg = default!;
+        [Dependency] private ILogManager _logMan = default!;
```

**Attempt 2 — green, verbatim:**

```
########## BUILD Content.Server (after 3-line DI fix) ##########
BUILD_EXIT=0
    185 Warning(s)
    0 Error(s)

########## BUILD Content.Client ##########
BUILD_EXIT=0
    266 Warning(s)
    0 Error(s)

########## BUILD full solution ##########
BUILD_EXIT=0
    131 Warning(s)
    0 Error(s)
```

`dotnet build SpaceStation14.slnx -c Release` produced **every** assembly
including `Content.Tests.dll` and `Content.IntegrationTests.dll` — so **Zig's two
wrapper test files compile against engine 284** with no diagnostics. Warnings are
`CS0618` obsolescence notices in *upstream's own* code (`Component.Owner`,
`GetTotalDamage`), not vs14's.

**Not done:** tests were compiled but **not executed** — build-green ≠ test-green,
and integration tests need postgres. `[inferred]` Runtime behaviour of the
wrapper UDS path under engine 284 is unverified; the `IsLocal`/`NetUserData`
changes in 277.2.0 sit near Zig's patch and deserve a live check.

---

## 7. Has upstream moved toward an agentic server? **No — it's flat.**

This was the highest-value question, so it was measured rather than skimmed.
**Across 879 content commits and 289 engine commits, the automation surface did
not grow.**

| Surface | At fork (Apr 12) | Now (Jul 25) | Δ |
|---|---|---|---|
| Engine toolshed commands | 216 | 216 | **0** |
| Content toolshed commands | 30 | 31 | **+1** |
| Content console commands | 207 | 211 | +4 |
| Files registering HTTP handlers | 4 | 4 (identical) | **0** |
| **HTTP admin endpoints** | **13** | **13** | **0** |

`Content.Server/Administration/ServerApi.cs` — the HTTP admin API, the single most
relevant file for an agentic server — changed by exactly **16 insertions / 16
deletions**, and every one is `[Dependency] private readonly X` → `[Dependency]
private X`. **Zero functional change.**

### The complete remote-control surface (unchanged, and this is the ceiling)

**Content `/admin/*`** — auth: `SS14Token` scheme, bearer value from the
`AdminApiToken` CVar:
```
GET   /admin/info · /admin/game_rules · /admin/presets
POST  /admin/actions/round/start · /round/end · /round/restartnow
POST  /admin/actions/kick · /ban · /add_game_rule · /end_game_rule
POST  /admin/actions/force_preset · /set_motd
PATCH /admin/actions/panic_bunker
```
**Engine status host:** `/status`, `/info`, `/download`, `/update`, `/shutdown`, `/teapot`

### The finding that actually matters for vs14d

```
grep 'ExecuteCommand|IConsoleHost' ServerApi.cs        → no matches
grep 'ExecuteCommand|ConsoleHost'  Robust.Server/ServerStatus → no matches
```

**There is no RCON. No console or toolshed execution over HTTP — not in content,
not in the engine.** The HTTP API is coarse round-management only (start/end a
round, kick, ban, set a game rule). Everything expressive — the 247 toolshed
commands, entity spawning, all fine-grained world manipulation — is reachable
**only** through an authenticated admin *client connection* or from server-side C#.

`[inferred]` **The strategic read:** an agentic vs14d cannot be built as an
external process driving a documented API, because that API tops out at
round-management. It must either (a) run an admin **client** and drive the
console over the game protocol, or (b) live **in-process as a C# content
system** — which, given Zig already ships in-process C# (the wrapper override)
and the sandbox was *widened* in 277 (`INumber`, `BigInteger`, `IParsable`,
`TensorPrimitives` now permitted), is the far better-supported path.

Genuinely useful things upstream *did* add, none aimed at automation but all usable:
- **277.0** — sandbox widened as above; `IEntityManager` **singleton-entity** API
  (`IEntityManager.Single.cs`) — a natural home for a persistent agent-state entity
- **277.1** — console commands can be **hidden** with a `_` prefix (an agent
  command namespace invisible to players); `CommandParsing.EscapeCommand()` for
  safely *constructing* command strings programmatically — directly useful if an
  agent synthesises console input; `FormattedStringBuilder`
- **279** — **Tracy profiling** integration; runtime `.ftl` locale upload
- **285** — `ChunkEntitySystem` PVS API; shutdown command accepts a reason

**Bottom line: tracking upstream makes the agentic idea neither easier nor
harder.** There is no incoming plugin system, no scripting host, no expanding
admin API to wait for or to be broken by. The control layer is vs14d's to build,
and the 104-day gap cost nothing strategically — only the 3-line DI migration.

---

## 8. State left behind

**Branch `vs14-upstream`** — restored to `7e1533848b`, **working tree clean**,
engine pin back at `85982545e`. Contains only this document.

**Branch `vs14-upstream-dryrun`** — **KEPT, local only, not pushed.** Three
commits on top of `7e1533848b`:
```
ef7e4c510b DRYRUN: migrate Ss14WrapperRemoteAddressOverride to RTB 277 DI sourcegen
ee0cc02439 DRYRUN: bump RobustToolbox to merged v284.0.0
5a9f39a3d6 DRYRUN: catch up to upstream-sw/master b92ce00026 + engine v284
```
This is the **proven-green catch-up**. Not pushed because its `RobustToolbox`
gitlink points at `3379cc1554e0ffa1aae271dbf650c8a0efb3bf79`, a merge commit that
exists **only** in this worktree's submodule gitdir
(`.git/worktrees/vs14-upstream/modules/RobustToolbox`) and on the local
submodule branch `dryrun-engine-catchup`. It is **not** on `azigler/RobustToolbox`,
so the superproject branch would be unusable elsewhere.

⚠️ **Removing this worktree destroys the engine merge commit.** It is cheap to
reproduce (conflict-free, one command — §4). To preserve it instead, push
`dryrun-engine-catchup` to `azigler/RobustToolbox` *first*, then push the
superproject branch. Deliberately not done: pushing to the engine fork is outside
this task's read-only-upstream remit.

**Upstream refs fetched** (additive objects only; nothing forced, nothing pushed):
`upstream-sw/master` → `b92ce00026`; RobustToolbox / cookbook / mapserver /
document-simu / robust-cdn / ss14-admin via `FETCH_HEAD`.

**Disk:** 175 G → 181 G at peak (~2.4 GB `bin/` + fetched objects); build
artifacts and stray `BuildChecker/` output removed; **settled at 176 G — net
~1 GB**, all of it fetched git objects.

---

## 9. Recommended next actions

1. **Land the catch-up** — it's done and green; the work is reviewing §5's ten
   resolutions, not redoing them.
2. **Re-apply the `LogWindowTest.cs` CI-flake fix** — resolved to upstream in the
   dry run; Zig's fix (`Bead: vs-4h1.x`) needs re-application onto upstream's version.
3. **Graft real ancestry** (`git replace --graft` + `filter-repo`) when no sibling
   agent is running — makes every future merge native.
4. **Delete 8 of 9 `upstream-*` remotes**; keep `upstream-sw`.
5. **Fix `.gitmodules`** — `branch = main` → `master` for `cookbook` + `mapviewer`.
6. **Run the test suite** — build-green is not test-green (§6).
7. **For vs14d: design for in-process C#, not an external API client** (§7).
