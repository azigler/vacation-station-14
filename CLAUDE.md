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

## Build & Test

```bash
python RUN_THIS.py                          # init submodules (first time)
dotnet build                                # build all
dotnet build --configuration DebugOpt       # optimized debug build
dotnet test Content.Tests --no-build        # unit tests
dotnet test Content.IntegrationTests --no-build  # integration tests
dotnet run --project Content.YAMLLinter     # validate prototypes
```

Alternative: a nix flake (`flake.nix`/`shell.nix`/`.envrc`) is inherited from
Delta-V for reproducible dev environments. Optional — not required by hooks or
skills. See `docs/DEVELOPMENT.md` for details.

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
