# Vacation Station 14

A curated [Space Station 14](https://github.com/space-wizards/space-station-14)
derivative, built with AI-assisted development. The base is pure SS14;
features from sibling forks are cherry-picked into directory-prefixed
subsystems. AGPLv3 license boundary anchored at the Phase 1 "Flavor A"
reset commit `86a6f6a3bee0c6ac62c1dabfe6e38d79c6c00d2d` (2026-04-12).

## Architecture

- **Engine**: [RobustToolbox](https://github.com/space-wizards/RobustToolbox) (C# / .NET 10, ECS) — submodule pin
- **Content split**: `Content.Server`, `Content.Client`, `Content.Shared`
- **Subsystem prefixes** (one per upstream fork we cherry-pick from):
  - `_VS/` — original Vacation Station 14 content (AGPL-3.0)
  - `_DV/` — Delta-V Station cherry-picks (introduced during Phase 5)
  - `_NF/` — Frontier Station cherry-picks (introduced during Phase 5)
  - `_RMC/` — RMC-14 cherry-picks (Aliens-mode, combat, scenario content)
  - `_HL/` — HardLight Sector cherry-picks (meta-aggregator — itself pulls from ~20 forks)
  - `_EE/`, `_Starlight/`, `_Corvax/`, … — other upstreams per curation plan
  - Unprefixed `Content.*` = pure SS14 upstream, MIT
- **Remotes**: `origin` (VS14), `upstream-sw` (space-wizards/space-station-14),
  `upstream-dv`, `upstream-nf`, `upstream-rmc`, `upstream-hl`. More added per
  Phase 5 curation output. No single remote is "the" upstream. See
  `docs/upstream-sync.md` for the full table.

## Code Conventions

We follow [upstream SS14 conventions](https://docs.spacestation14.com/en/general-development/codebase-info/conventions.html),
adapted with our subsystem-prefix discipline.

### Style
- File-scoped namespaces, Allman braces
- 4-space indent (C#), 2-space indent (YAML, XML)
- UTF-8, LF line endings, max 120 chars
- `var` preferred, `_camelCase` private fields, `PascalCase` public
- Classes must be `abstract`, `static`, `sealed`, or `[Virtual]`

### Content Organization
All new content goes in `_VS` subdirectories:
- `Content.Server/_VS/`, `Content.Shared/_VS/`, `Content.Client/_VS/`
- `Resources/Prototypes/_VS/`, `Resources/Locale/en-US/_VS/`
- `Resources/Textures/_VS/`, `Resources/Audio/_VS/`

### Upstream Modifications
When modifying non-`_<fork>/` files, annotate changes with the subsystem
prefix corresponding to the author (VS for VS14, DV for Delta-V cherry-picks
that edit an unprefixed file, NF for Frontier, etc.):
- **C#**: `// VS - <explanation>` / `// DV - <explanation>` on changed lines
- **YAML**: `# VS - <explanation>` on changed lines
- **Blocks**: `// VS - start` ... `// VS - end`
- **Fluent**: Move changed strings to the corresponding `_<fork>/` file,
  comment out originals
- **Partial classes**: Preferred for substantial C# additions to upstream types

### Entity IDs
PascalCase, category prefix. Append `VS` suffix when disambiguation needed:
`ClothingHeadHatChefVS`, `FoodRecipePastaVS`

## Dev Environment

**Nix is the primary dev path.** The flake pins the entire build + ops
toolchain (`dotnet-sdk_10`, graphics libs, `shellcheck`, `yamllint`,
`promtool`, `loki`, `grafana-cli`, pre-commit). `services-flake` additionally
provides a local postgres + prometheus + loki + grafana stack.

```bash
direnv allow                                # one-time per worktree
# cd-triggered env load handles the rest

nix develop                                 # alternative: manual shell
nix run .#dev-services                      # local dev stack (postgres/prom/loki/grafana)
```

The flake evaluates on `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`,
and `aarch64-darwin`. Linux gets the full client+server shell, macOS gets
a server-only shell (client needs a Linux VM), and Windows contributors
run the same nix flow inside WSL2. System-install (`./setup.ubuntu.sh`)
remains supported and is the only path for production hosts. See
`.claude/skills/nix/SKILL.md` and `docs/DEVELOPMENT.md` for detail,
including the WSL2 subsection and platform-support matrix.

## Build & Test

```bash
python RUN_THIS.py                          # init submodules (first time)
dotnet build                                # build all
dotnet build --configuration DebugOpt       # optimized debug build
dotnet test Content.Tests --no-build        # unit tests
dotnet test Content.IntegrationTests --no-build  # integration tests
dotnet run --project Content.YAMLLinter     # validate prototypes
```

### Nix env in worktree subagents

The `session-start.sh` hook runs `direnv allow .` in every worktree that has
an `.envrc`, so the per-path approval is always in place. However, non-
interactive shells spawned by the agent's Bash tool do not have a `direnv
hook` wired in (we deliberately don't touch user-global dotfiles), so the
flake env does not auto-activate on `cd`.

In practice the orchestrator's env (nix paths already resolved from the main
worktree's `.envrc`) is inherited by subagent shells, so `dotnet`, etc.
usually Just Work. If a subagent needs to guarantee the flake toolchain is
active — e.g. before invoking `dotnet`, `shellcheck`, or any tool it expects
to come from the flake rather than the system — prepend this to the command:

```bash
eval "$(direnv export bash)" 2>/dev/null; dotnet build
```

This is belt-and-suspenders: safe no-op if already active, cheap on repeat
invocations thanks to the local nix store cache.

The flake now pins ops validation tools alongside the build toolchain:
`shellcheck`, `yamllint`, `promtool` (via `prometheus`), `loki` + `logcli`
(via `grafana-loki`), and `grafana-cli` (via `grafana`). Subagents and ops
scripts should rely on these from the flake env instead of reaching for
`apt-get install shellcheck` or `pip install yamllint` mid-run. To guarantee
they're on PATH in a non-interactive agent shell, prepend the same direnv
export pattern:

```bash
eval "$(direnv export bash)" 2>/dev/null; shellcheck script.sh
eval "$(direnv export bash)" 2>/dev/null; promtool check config prometheus.yml
```

## Upstream Sync

Multiple remotes, per-upstream mode (submodule / cherry-pick / deploy-as-is).
See [`docs/upstream-sync.md`](docs/upstream-sync.md) for the per-upstream
table and [`.claude/skills/upstream-sync/SKILL.md`](.claude/skills/upstream-sync/SKILL.md)
for the cherry-pick workflow.

Quick per-remote fetch:
```bash
git fetch upstream-sw     # engine + base content (checkout, not merge)
git fetch upstream-dv     # Delta-V cherry-pick source
# other upstreams added per Phase 5 curation
```

Conflict bias when cherry-picking: keep our `_VS/` edits, merge
`_<other-fork>/` carefully (preserve upstream author's intent).

## Commit Convention

```
<gitmoji> scope: short description

Optional body.

Bead: <bead-id>
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

Always push after commit unless in a worktree branch.

### Changelog Format
```
:cl: YourName
- add: Added a thing
- remove: Removed a thing
- tweak: Changed a thing
- fix: Fixed a thing
```
Use `VSADMIN:` for admin changelog (never `ADMIN:` or `DELTAVADMIN:`).

## Development Pipeline

```
/orient → /spec → /review → /test → /impl → /branch
```

See `.claude/skills/` for each workflow. `/orient` is the session entry point.

## License

AGPLv3 license boundary anchored at Flavor A clear commit
`86a6f6a3bee0c6ac62c1dabfe6e38d79c6c00d2d` (2026-04-12) per the
HardLight attribution pattern.

- **`_VS/` code**: AGPL-3.0
- **Unprefixed `Content.*` code**: MIT (SS14 upstream), sublicensed AGPLv3
- **`_DV/` code** (Phase 5+): AGPL-3.0 (matches Delta-V post-boundary)
- **Other `_<fork>/` subsystems** (Phase 5+): per-fork license per
  README attribution table
- **`RobustToolbox/`** (submodule): MIT
- **Assets**: CC-BY-SA 3.0 unless noted; some CC-BY-NC-SA 3.0 (compliant
  while VS14 remains non-monetized)

See `README.md` (summary table) and `LEGAL.md` (authoritative detail +
per-service deployment obligations).
