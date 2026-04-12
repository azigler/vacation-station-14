# Vacation Station 14

A hard fork of [Delta-V Station](https://github.com/DeltaV-Station/Delta-v), built
with AI-assisted development. AGPL-3.0 for new code, MIT inherited from upstream.

## Architecture

- **Engine**: [RobustToolbox](https://github.com/space-wizards/RobustToolbox) (C# / .NET 10, ECS)
- **Content split**: `Content.Server`, `Content.Client`, `Content.Shared`
- **Custom code prefix**: `_VS` (all Vacation Station-original content)
- **Upstream**: Delta-V as `upstream` remote, Space Wizards as engine submodule

## Code Conventions

We follow [upstream SS14 conventions](https://docs.spacestation14.com/en/general-development/codebase-info/conventions.html)
and [Delta-V contributing guidelines](https://github.com/DeltaV-Station/Delta-v/blob/master/CONTRIBUTING.md),
adapted for our `_VS` prefix.

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
When modifying non-`_VS` files, annotate changes:
- **C#**: `// VS - <explanation>` on changed lines
- **YAML**: `# VS - <explanation>` on changed lines
- **Blocks**: `// VS - start` ... `// VS - end`
- **Fluent**: Move changed strings to `_VS` file, comment out originals
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

Delta-V is the `upstream` remote. Periodic sync:
```bash
git fetch upstream
git merge upstream/master
# Resolve conflicts: always keep _VS code, merge upstream carefully
dotnet build && dotnet test Content.Tests --no-build
```

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

- **New `_VS` code**: AGPL-3.0
- **Upstream SS14 code**: MIT + AGPL-3.0
- **Delta-V `_DV` code**: AGPL-3.0
- **Starlight `_Starlight` code**: Custom MIT-like, sublicensed to AGPL-3.0
- **Assets**: CC-BY-SA 3.0 unless marked otherwise; some CC-BY-NC-SA 3.0

See `LEGAL.md` for full details.
