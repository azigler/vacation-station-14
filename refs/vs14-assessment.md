# vs14 — state-of-the-repo assessment

**Date:** 2026-07-26 · **Bead:** `explore-9ct8` · **Branch:** `vs14-assess`
**Purpose:** establish what actually exists in `~/vacation-station-14` before
anyone designs `~/vs14d` (a fully agentic, self-controlling SS14 server).

Every claim below is tagged **[M]** measured on this machine today, or
**[I]** inferred. Where a number could drift, the command is given.

> **Scope note.** Upstream drift / sync strategy is a sibling agent's
> assignment and is deliberately NOT analysed here. One upstream fact is
> recorded because it invalidates a naive measurement — see
> [The moving-ref trap](#the-moving-ref-trap).

---

## 0. The one-paragraph answer

**vs14 is not a game fork. It is an ops/infrastructure project wrapped
around a stock, unmodified Space Station 14.** [M] Of the 33,682 lines
Zig authored on top of upstream, **963 lines (2.9%) are C# game code**;
the rest is documentation, systemd units, shell, a Go network shim, a
Next.js site, Grafana dashboards, and agent harness. [M] The engine fork
is 2 commits. [M] It **builds clean today** (0 errors). [M] It was played
by exactly **one human, ever** — Zig. [M] The web/content/admin surface
is **still live and serving 200s**; only the game server itself is off.
So "tabled" is much narrower than it sounds, and a migration carries far
less game-code baggage than the 14 GB working tree suggests.

---

## 1. What this repo actually is

### Shape [M]

| Metric | Value | How measured |
|---|---|---|
| Working tree on disk | **14 GB** | `du -sh` (includes submodules + build output) |
| Tracked files | **42,133** | `git ls-files \| wc -l` |
| Commits on `main` | **380** | `git rev-list --count HEAD` |
| Commits authored by Zig | **380 (100%)** | `git shortlog -sn HEAD` |
| First commit | 2026-04-11 | `:tada: init: hard fork of Delta-V Station` |
| Last commit | 2026-07-26 | docs fix (commit-trailer template) |
| Tags | 2 (`flavor-a-baseline-2026-04-12`, `pre-flavor-a-clear`) | `git tag` |
| Remotes | **10** (`origin` + 9 `upstream-*`) | `git remote -v` |

**The history is a hard fork, not a fetch-and-merge.** [M] `git merge-base
flavor-a-baseline-2026-04-12 upstream-sw/master` returns **empty** — there is
no shared history with space-wizards. Commit 1 imported the whole tree as a
snapshot; every one of the 380 commits is Zig's. This is why author-based
attribution is useless here and why the tree-diff method below is the only
honest way to split local from upstream.

File-type census of the tracked tree [M] (`git ls-files | sed 's/.*\.//' | sort | uniq -c`):
25,263 `.png` · 7,600 `.cs` · 3,086 `.json` · 2,592 `.yml` · 1,286 `.ogg` ·
1,178 `.ftl`. **Overwhelmingly upstream game assets and content.**

### Submodule tree [M] (`git submodule status` — all 8 initialised and checked out)

| Path | Upstream | Pin | Note |
|---|---|---|---|
| `RobustToolbox` | **`azigler/RobustToolbox`** | `85982545e` | **Zig's own engine fork** — see §2 |
| `external/ss14-admin` | `space-wizards/SS14.Admin` | `b5ab8606` (v1.9.1) | Web admin panel |
| `external/mapserver` | `space-wizards/SS14.MapServer` | `8f2362b3` | Map tile server |
| `external/mapviewer` | `space-wizards/SS14.MapViewer` | `e48f0a76` | Map browser UI |
| `external/robust-cdn` | `space-wizards/Robust.Cdn` | `0b2b814e` (v2.2.0-3) | Client-download CDN |
| `external/cookbook` | `arimah/ss14-cookbook` | `f4b733e1` | Chemistry/recipe site |
| `external/document-simu` | `yagwog/RMC14-document-simu` | `6757e6eb` | In-fiction document writer |
| `external/nurseshark` | **`azigler/nurseshark`** | `1472e376` | **Zig's own** medical/cryo companion app |

Two of eight submodules are Zig's own repos. The other six are
deploy-as-is third-party services. [I] The `external/<name>` +
`ops/<name>` naming pairing is an enforced convention (stated in
`CLAUDE.md`) and holds for every entry.

---

## 2. Zig's work versus upstream — **the number that matters**

### Method

Author attribution is meaningless (100% of commits are his, because of the
hard-fork import). The honest measure is a **tree diff against the
contemporaneous upstream tip** — the commit upstream was at when the
baseline was cut.

```bash
# ee0f4050ef = space-wizards/space-station-14 @ 2026-04-12, the day of the
# "Flavor A" reset. Use the PINNED SHA, never the moving ref (see §2.4).
git diff --shortstat ee0f4050ef HEAD
```

### 2.1 Headline [M]

```
275 files changed, 33,682 insertions(+), 218 deletions(-)
```

**Only 218 lines of upstream were deleted.** [I] Upstream SS14 is
essentially pristine; Zig's work is almost entirely *additive*, sitting
alongside the game rather than inside it. That is the single most
migration-friendly fact in this document.

### 2.2 What those 33,682 lines are [M]

```bash
git diff --numstat ee0f4050ef HEAD | awk -F'\t' \
 '{n=split($3,p,"/");m=split(p[n],q,".");e=(m>1)?q[m]:"none";i[e]+=$1;c[e]++}
  END{for(x in i)printf "%5d files %7d ins  .%s\n",c[x],i[x],x}' | sort -k3 -rn
```

| Kind | Files | Lines | What it is |
|---|---:|---:|---|
| `.md` | 44 | **7,987** | Docs — `OPERATIONS.md` alone is 54 KB |
| `.json` | 11 | 6,379 | Grafana dashboards, web config |
| `.py` | 3 | 5,872 | `ops/guidebook/render.py` + its tests |
| `.sh` | 33 | 3,531 | Ops install/build/backup scripts |
| `.go` | 9 | **2,157** | `ops/ss14-wrapper` — the PROXY-protocol shim |
| `.yml` | 26 | 1,395 | CI workflows, prometheus/loki config |
| `.tsx`/`.ts` | 14 | 1,574 | The Next.js public site |
| **`.cs`** | **6** | **963** | **The entire C# game-code contribution** |
| `.service`/`.timer` | 11 | 366 | systemd units |
| `.conf` | 1 | 283 | nginx vhost |

**Game code is 2.9% of his authorship.** [M] Every C# file he added:

```
Content.Server/Connection/Ss14WrapperRemoteAddressOverride.cs   (new)
Content.Server/IoC/ServerContentIoC.cs                          (2-line registration)
Content.Tests/Connection/Ss14WrapperCvarTests.cs                (new, tests)
Content.Tests/Connection/Ss14WrapperRemoteAddressOverrideTests.cs (new, tests)
Content.IntegrationTests/Tests/Administration/Logs/LogWindowTest.cs (minor)
Content.Shared/Movement/Systems/MovementModStatusSystem.cs       (4 lines)
```

[M] **All of it exists to serve the network wrapper.** There is no
gameplay content. The only game-flavoured additions are 6 Guidebook XML
pages + 2 YAML/FTL files under `_VS/` (community welcome/rules/etiquette
text, 278 lines total) — prose, not mechanics.

### 2.3 The engine fork [M]

`RobustToolbox` points at `azigler/RobustToolbox`, which is upstream
`3136118b5` (Version 275.2.0, 2026-03-29) **plus exactly two commits**:

```
c88d126ec :sparkles: net: add IRemoteAddressOverride hook for wrapper-aware deploys
85982545e :bug: net: ServerAuth.cs:49 isLocal must consult IRemoteAddressOverride
```

[I] This is a genuinely small, well-scoped engine patch — a rebase onto a
newer RobustToolbox is a two-commit cherry-pick, not a merge campaign.

### 2.4 The moving-ref trap ⚠️

[M] Mid-assessment, `upstream-sw/master` advanced from `ee0f4050ef`
(2026-04-12) to `b92ce00026` (2026-07-25) because the sibling upstream-sync
agent ran a fetch — **remotes are shared across git worktrees.** The same
diff command then reported *5,734 files / 213,028 insertions / 225,149
deletions* instead of 275/33,682.

Both numbers are real, and they answer different questions:

- **275 files / 33,682 lines** = *what Zig built* (vs. contemporaneous upstream). **Use this one.**
- **5,734 files** = *Zig's work + 3.5 months of upstream drift*. That's the sibling agent's problem.

**Anyone re-deriving these numbers must pin the SHA `ee0f4050ef`.** A ref
name will silently give a different answer depending on when it was last
fetched — a measurement that fails silently, which is exactly the class of
bug this assessment is meant to catch.

---

## 3. What runs, and how

### Toolchain [M]

| Need | Required | Present on this box | OK? |
|---|---|---|---|
| .NET SDK | `10.0.100` (`global.json`, `rollForward: latestFeature`) | `10.0.109` at `/usr/bin/dotnet` | ✅ |
| ASP.NET runtime | 10.x | `10.0.9` | ✅ |
| Go | (for `ss14-wrapper`) | `go1.24.4` | ✅ |
| Nix + direnv | primary dev path per `CLAUDE.md` | both present | ✅ |
| PostgreSQL | 14+ | running, `vacation_station` DB present | ✅ |

### Does it build TODAY? **Yes.** [M]

```
$ dotnet build Content.Server --nologo -v minimal
    303 Warning(s)
    0 Error(s)
Time Elapsed 00:01:33.64
```

Exit code **0**. All 303 warnings are upstream `CS0618` obsolete-API
notices (`Component.Owner`, `RandomExtensions.*`, `ISawmill`) — none
originate in Zig's files. [M] No submodule init was needed; all 8 were
already checked out in the fresh worktree.

**Artifact note:** this build wrote **305 MB** to `bin/`, taking the
worktree to 1.7 GB. `bin/`+`obj/` are gitignored and were left in place
(deleting them costs a future agent another 94 s); they are removable with
`git clean -xdf bin obj`.

### Entrypoints [M]

| Path | What |
|---|---|
| `runserver.sh` / `runclient.sh` (+ `.bat`, `-Debug`, `-Quick`, `-Tools` variants) | Dev launchers |
| `RUN_THIS.py` | Submodule init |
| `setup.ubuntu.sh` / `setup.postgres.sh` / `setup.watchdog.sh` | Host provisioning (166 / 109 / 194 lines) |
| `instances/vacation-station/config.toml.example` | **The server config — richly commented, the best single doc in the repo** |
| `ops/*/install.sh` (20 shell scripts, 19 systemd units, 2 docker-compose) | Per-service deploy |

### Deployed topology [M]

Two hosts, and the split is not obvious from the repo:

- **zig-computer** (this box, public IP `51.81.33.136`) — public TLS edge
  only. nginx vhost `vs14.zig.computer.conf`. Everything except
  `/instances/ /client.zip /watchdog/` is proxied to pico.
- **pico** (headless Mac, tailnet `100.72.47.4`, `ssh pico` port 2222,
  up 58 days) — holds **all** content and state: the live postgres, the
  containers (cdn/mapserver/ss14-admin/grafana/loki/prometheus), the web
  service, the static site builds, and the watchdog instance dir.

[M] systemd units on zig-computer: 10 services + 8 timers named
`vs14-*`/`ss14-*`, **all `disabled`**. `ss14-watchdog.service` is
`disabled`. No `Robust.Server` process is running on either host.
The mac-side equivalents are launchd agents under
`~/Library/LaunchAgents/` on pico (11 plists).

### State / data [M]

| Thing | Where | Size / count |
|---|---|---|
| Live game DB | pico, `vacation_station` (40 tables) | 30,610 admin_log rows |
| **Stale duplicate DB** | zig-computer `vacation_station` + `_mapserver` | nothing uses it — see §4 |
| DB backups | pico `~/backups/vacation-station/` | 62 files, 22 MB, newest 2026-07-25 |
| Client release zip | `release/SS14.Client.zip` | 200 MB (2026-05-25) |
| Replays | pico instance `data/replays/` | **0 files** — see §4 |

---

## 4. What is broken or rotted

Ordered by how badly it would mislead someone planning `~/vs14d`.

### 4.1 🔴 `/opt/vacation-station` is a symlink to the dev tree — the documented prod/dev split does not exist [M]

`CLAUDE.md` states, as operating discipline:

> Prod runs from a second repo clone at `/opt/vacation-station/`, kept in
> sync with origin via `git pull` — **never direct-edit files there**.

Reality:

```
$ ls -la /opt/vacation-station
lrwxrwxrwx 1 root root 32 Apr 12 05:14 /opt/vacation-station -> /home/ubuntu/vacation-station-14
```

[M] There is one tree, not two. [M] **96 references to `/opt/vacation-station`**
across `ops/`, `web/`, `docs/` all resolve into the development checkout.
[I] Any ops script that "deploys to prod" is editing the dev tree, and the
entire "edit in `/home/` → push → `git pull` in `/opt/`" propagation ritual
in the docs is a no-op. This is the highest-value correction in this
document: a `~/vs14d` design that assumes an isolated prod tree would be
designing against a fiction.

### 4.2 🔴 Every backup checksum sidecar is empty — verification is theatre [M]

```
$ find ~/backups/vacation-station -name "*.sha256" -size 0 | wc -l
      31       # of 31 total
```

All 31 `.sha256` files are **0 bytes**. The `.dump` files themselves are
real and current (730 KB, 2026-07-25). [I] So backups *are* being taken —
but nothing can verify one is intact, and the failure is completely silent:
the sidecar exists, so a naive "is there a checksum?" check passes.

Corollary [M]: `refs/session-handoff.md` (2026-07-12) warns "no confirmed
backups since 2026-05-24". **That warning is now stale** — daily dumps have
run continuously through 2026-07-25. The handoff is wrong in the reassuring
direction on the checksums and wrong in the alarming direction on the dumps.

### 4.3 🟠 Five pico launchd agents last exited nonzero, silently [M]

`launchctl list` on pico, last-exit-status column:

| Agent | Exit |
|---|---|
| `com.zig.vs14-guidebook-build` | **128** |
| `com.zig.ss14-backup` | **127** (command not found) |
| `com.zig.vs14-web` | 1 |
| `com.zig.vs14-map-render` | 1 |
| `com.zig.vs14-cookbook-build` | 1 |

[I] Nothing alerts on these. `ss14-backup` exiting 127 alongside a
successful 2026-07-25 dump suggests a *partial* failure — likely the
checksum step (§4.2) is the missing command. That is a concrete,
testable hypothesis, not a confirmed cause.

### 4.4 🟠 Replays never recorded, despite being configured [M]

`instances/vacation-station/config.toml.example` sets `auto_record = true`
and comments the feature as **"used as training-data source"**. On pico:

```
$ find ~/ss14-watchdog/instances/vacation-station/data/replays -type f | wc -l
       0
```

[I] Either recording never worked, or `ops/replays/rotate.sh` deleted
everything. Either way, the richest imaginable agentic input stream — a
full state-snapshot recording of every round — **has zero data in it.**

### 4.5 🟡 The 503'd nginx locations [M]

`/etc/nginx/sites-available/vs14.zig.computer.conf` returns honest 503s on
`/instances/`, `/client.zip`, `/watchdog/`, annotated `TABLED 2026-07-25`.
[M] Confirmed live: `curl https://vs14.zig.computer/client.zip` → **503**.
Restoration is documented inline (delete three blocks, uncomment the proxy
blocks below, `nginx -t && systemctl reload nginx`). This is tidy, not
rotted — it is the one piece of the stand-down that was done carefully.

### 4.6 🟡 A stale duplicate database on the wrong host [M]

zig-computer's postgres holds `vacation_station` + `vacation_station_mapserver`
that nothing reads. It is a **frozen April snapshot**: 1 player, 9 rounds,
6,083 admin_log rows, last activity 2026-05-23. The live DB on pico has
30 rounds and 30,610 rows. [I] A future agent querying "the database" on the
local host gets plausible-looking but months-stale answers with no error —
precisely the fail-silent class. (I hit this myself during this assessment.)

### 4.7 🟢 Non-issues, checked and cleared

- **Hardcoded tailnet IP `100.95.4.73`** appears 15× [M] — but only in Go
  *test fixtures* and README examples, never in live config. pico's real IP
  is `100.72.47.4`. Harmless.
- **Secrets** [M] — `.env.secrets`, `ops/ss14-admin/.env`, and
  `ops/observability/secrets/` are all gitignored; `git ls-files` shows no
  tracked secret files. Clean.
- **GitHub Actions** [M] — 28 workflows present; Actions deliberately
  disabled at the repo level (bead `vs-2f8.12` tracks reassessment). Not rot.

---

## 5. The agentic surface that already exists

### Harness inventory [M]

| Artifact | State |
|---|---|
| `CLAUDE.md` | 240 lines, current — subsystem-prefix discipline, license boundary, bead conventions |
| `.claude/skills/` | **9 project skills**: `build`, `changelog`, `nix`, `prototype`, `services`, `upstream-sync`, `vibe-maintainer`, `vs14-brand`, `vs14-voice` |
| `hooks/` | 9 hook scripts (lint-on-write, pre-commit, session-start/end, task-completed) |
| `.beads/` | prefix `vs-`, **30 beads / 26 open** |
| `refs/session-handoff.md` | 2026-07-12, detailed — but stale in two places (§4.2) |
| `docs/` | 2,830 lines across 7 files + a `community/` subtree |

**Reusable, and genuinely good:** `vibe-maintainer/SKILL.md` is a
maintainer playbook explicitly written for the *"one human + AI, no
volunteer review team"* operating model — PR triage tiers, a decision tree,
attribution rules. [I] It is the closest thing in the repo to a stated
philosophy for `~/vs14d`, and it was written before the idea existed.
Paired with `.github/workflows/auto-merge.yml` + `pr-triage.yml`, there is
already a working *agentic maintainership* loop, separate from any
agentic *gameplay* loop.

**Abandoned:** [M] 10 skills that existed at the baseline
(`beads`, `commit`, `impl`, `lint`, `orchestrator`, `orient`, `review`,
`spec`, `test`, `branch`) were deleted — [I] absorbed into the global
`~/.claude/skills/` set. `CLAUDE.md` still advertises the pipeline
`/orient → /spec → /review → /test → /impl → /branch`, but **`/orient`,
`/review`, `/spec`, `/test`, `/impl`, `/branch` no longer exist in this
repo** — a dead reference in an always-loaded file.

### Bead store — themes only [M] (30 total, 26 open; bodies not dumped)

- **ops hardening** (~11): CDN hang, pico boot-resilience, blackbox
  monitoring, retention verification, Actions budget
- **community launch** (~8): Discord bootstrap, welcome/rules channels,
  hub advertising — all `human:`-prefixed, none started
- **architecture** (~4): the `vs-ddu` P1 epic (Flavor A cherry-pick campaign)
  — Phases 4 & 5 never executed
- **features** (2): persistent community goals, shift summaries (both
  "inspired by Wayfarer", both P3, never started)
- **wrapper** (1): `vs-4h1`, the only bead **in progress**

[I] The backlog is overwhelmingly ops-and-community, not gameplay. It
reads as a server *launch* plan that stopped one step before launch.

---

## 6. Operational reality — was it ever really played?

**Measured against the live pico database.** The answer is unambiguous.

| Metric | Live DB (pico) | Stale DB (zig-computer) |
|---|---:|---:|
| **Distinct players, all time** | **1** | 1 |
| Rounds | 30 | 9 |
| `player_round` entries | 9 | 2 |
| Character profiles | 1 | 1 |
| Connection-log rows | 0 | 1 |
| admin_log rows | 30,610 | 6,083 |
| Bans | 1 | 0 |

[M] The single player is `spacezig` — Zig. First seen 2026-04-12,
**last seen 2026-06-11**. [M] Rounds continued to tick over until
**2026-07-09**, a month after the last human presence: the station was
running empty, cycling rounds for nobody. [M] `hub.advertise = false` in
the config template — it was never listed on the public server browser.

**Verdict [I]: it was stood up, thoroughly instrumented, and never
populated.** The 30,610 admin_log rows are the game engine logging its own
simulation, not a community. This matters directly for `~/vs14d`: there is
**no human-behaviour corpus** here. Whatever "self-controlling" means, it
cannot mean *learned from how this server was played* — it must mean
driving an empty station, or generating its own population.

[I] The flip side is unusually clean: no player data to migrate, no bans to
honour, no community to disrupt, no backwards-compatibility obligations.
`~/vs14d` gets a genuinely free hand.

---

## 7. Seams an agent could observe and act through

Concrete, path-anchored. This is the raw material.

### 7.1 ⭐ `Content.Server/Administration/ServerApi.cs` — a token-authed HTTP control plane [M]

**797 lines, upstream SS14, already in the tree, already builds.** This is
the RCON-equivalent, and it is better than an RCON.

```
GET   /admin/info                      # full server state
GET   /admin/game_rules                # available rules
GET   /admin/presets                   # available presets
POST  /admin/actions/round/start
POST  /admin/actions/round/end
POST  /admin/actions/round/restartnow
POST  /admin/actions/kick
POST  /admin/actions/ban
POST  /admin/actions/add_game_rule     # ← inject an antag / event mid-round
POST  /admin/actions/end_game_rule
POST  /admin/actions/force_preset
POST  /admin/actions/set_motd
PATCH /admin/actions/panic_bunker
```

Auth [M]: `Authorization: SS14Token <token>`, token from the
`CCVars.AdminApiToken` cvar, hot-reloadable
(`_config.OnValueChanged(CCVars.AdminApiToken, …)`).

[I] **This alone is enough for a first agentic loop.** An agent can read
state and *change the course of a round* — add a game rule, force a preset,
restart, rewrite the MOTD — over plain authenticated HTTP, with zero new
C#. It is the shortest path from "tabled server" to "server an agent
drives".

### 7.2 ⭐ Toolshed — an in-game command language [M]

`RobustToolbox/Robust.Shared/Toolshed/` (upstream) plus **30 files in
`Content.Server`/`Content.Shared` defining `ToolshedCommand`s** [M].
Toolshed is SS14's typed, pipeline-style console language — the expressive
tier above the fixed admin-API verbs.

[I] Where the admin API gives ~12 coarse actions, Toolshed can address
entities, components and systems individually. [I] It is reachable from the
admin console; whether it is reachable *over HTTP* is **not verified** and
is the single highest-value follow-up question for `~/vs14d` — if it is (or
can cheaply be made) remotely invocable, that is the difference between an
agent that can restart a round and an agent that can build things.

### 7.3 ⭐ Read seams — status, metrics, logs [M]

| Seam | Address | Shape |
|---|---|---|
| Game `/status` + `/info` | `127.0.0.1:1212` | JSON: players, `round_id`, `run_level`, preset, map, build |
| Prometheus metrics | `*:44880` | Robust.Server internals: tick times, entity count, GC, player count |
| Loki log push | `http://localhost:3100`, label `Server=vacation-station` | **Structured** server logs via Serilog |
| Grafana | pico container, 3 provisioned dashboards | `ops/observability/grafana/dashboards/` |

[M] A worked example of consuming the first one already exists:
`web/app/api/server-status/route.ts` fans out to `/info` + `/status`,
merges, and caches for 15 s. [I] An agent's observation layer is
**already built and instrumented** — Loki in particular means the agent can
query structured logs rather than scrape stdout.

### 7.4 `ops/ss14-wrapper` — a Unix-socket API in front of the netcode [M]

Zig's own 2,157-line Go daemon (9 files, unit-tested). Strips PROXY-protocol
headers and exposes a **newline-delimited text API over a Unix domain
socket**:

```
HEALTH              → "OK active_sessions=N uptime_s=X"
ENUMERATE           → "<proto> <port> <real-ip>:<real-port>" … "END"
LOOKUP udp 33000    → "OK <real-ip>:<real-port>" | "MISS"
```

[I] Its purpose is IP resolution for moderation, but the shape — a
trivially-scriptable local socket sitting in the packet path, paired with
an engine hook (`IRemoteAddressOverride`) already merged into Zig's
RobustToolbox — makes it the natural place to add **per-connection
observation or intervention** without touching the game loop.

### 7.5 The watchdog — process lifecycle [M]

`SS14.Watchdog` on `127.0.0.1:5000`, token-authed (`openssl rand -hex 32`,
generated by `setup.watchdog.sh`), exposing restart / shutdown / stats.
[I] This is the *outer* control loop: the admin API changes what happens
inside a round; the watchdog API changes whether the server exists. An
agent that can do both can recover from its own mistakes.

### 7.6 File-based seams [M]

- `instances/vacation-station/config.toml` — the entire server
  configuration, plain TOML, read at startup. [I] Agent-writable.
- `docs/community/*.md` + `events.yml` — MOTD, rules, server description,
  and an events calendar, all consumed by the site *and* the config. [I] An
  agent editing `motd.md` changes what players see.
- Replay zips — [M] configured (`auto_record = true`, path template
  `{year}/{month}/round_{round}-…zip`), commented as a training-data
  source, **currently empty** (§4.4). [I] The highest-ceiling seam in the
  repo and the one requiring the most repair.

### 7.7 Agentic maintainership (distinct from agentic gameplay) [M]

`.github/workflows/auto-merge.yml` + `pr-triage.yml` + the
`vibe-maintainer` skill implement label-driven PR triage and soak-gated
auto-merge. [I] `~/vs14d` has two plausible agentic loops, and this one
already partly works. Worth deciding deliberately which is meant.

---

## 8. Fork / submodule / rebuild — what the measurements imply

Not a recommendation; the inputs to one.

| Option | Supported by | Undercut by |
|---|---|---|
| **Rebuild `~/vs14d` fresh from upstream SS14, port the 963 lines** | [M] Game-code contribution is 963 lines in 6 files, of which 4 are the wrapper feature + its tests. [M] Engine fork is 2 commits. [M] Only 218 upstream lines were ever deleted. | [M] Discards 33 shell scripts, 19 systemd units, 2,830 lines of ops docs, and a working 8-submodule service topology — the actual bulk of 3 months' work. |
| **Fork/branch this repo** | [M] It builds clean today. [M] The whole deployed topology is here and mostly still live. | [M] Carries a 14 GB tree, 42k files, and 3.5 months of upstream drift (5,734 files) that must be resolved anyway. |
| **Submodule vs14 under `~/vs14d`** | [I] Cleanly separates "the SS14 server" from "the agent that drives it" — and every seam in §7 is *external* (HTTP, UDS, files), so an agent does not need to live in the C# tree. | [I] The 963 lines of C# and the 2 engine commits still need a home; a submodule pin makes upstream rebases someone's explicit job rather than an implicit one. |

[I] The measurements lean toward **treating the game server as a
replaceable dependency and the ops/agent layer as the durable asset** —
because that is empirically what Zig built. The 2.9% figure is the whole
argument.

---

## 9. Reproducing these numbers

```bash
cd /home/ubuntu/vacation-station-14

# The local-vs-upstream split — PIN THE SHA (§2.4)
git diff --shortstat ee0f4050ef HEAD          # → 275 files, 33,682+, 218-
git diff --name-status ee0f4050ef HEAD -- Content.Server Content.Shared Content.Tests

# Build
dotnet build Content.Server --nologo -v minimal   # → 0 Error(s), ~94s, writes 305MB

# Live DB (pico, NOT the stale local copy — §4.6)
ssh pico '/opt/homebrew/bin/psql -d vacation_station -c \
  "SELECT (SELECT count(*) FROM player), (SELECT count(*) FROM round);"'

# Silent-failure checks
ssh pico 'launchctl list | grep -iE "ss14|vs14"'                       # §4.3
ssh pico 'find ~/backups/vacation-station -name "*.sha256" -size 0 | wc -l'  # §4.2
ls -la /opt/vacation-station                                            # §4.1
```

---

## 10. Open questions for the `~/vs14d` designer

1. **Is Toolshed invocable over HTTP?** [I] Unverified. Determines whether
   an agent gets ~12 coarse verbs or the full command language (§7.2).
2. **Why are the replays empty** — never recorded, or rotated away? (§4.4)
   Determines whether the richest observation stream is recoverable.
3. **Agentic gameplay or agentic maintainership** — §7.7 shows the repo
   already leans toward the latter. Which is `~/vs14d`?
4. **With one player ever and no behaviour corpus, what does
   "self-controlling" optimise for?** An empty station has no feedback
   signal (§6).
5. **Does the `/opt` fiction (§4.1) get fixed or formalised?** A real
   prod/dev split is a prerequisite for an agent that deploys itself.
