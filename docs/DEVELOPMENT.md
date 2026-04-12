# Developing Vacation Station 14

## Quick Start

```bash
git clone https://github.com/azigler/vacation-station-14.git
cd vacation-station-14
./setup.ubuntu.sh
dotnet run --project Content.Server    # headless
dotnet run --project Content.Client    # needs GPU/audio
```

Connect via launcher → Direct Connect → `localhost`.

## Prerequisites

- .NET 10 SDK
- Python 3.7+ (for `RUN_THIS.py`)
- Git
- Ubuntu 22.04 / 24.04 or equivalent

See [setup.ubuntu.sh](../setup.ubuntu.sh) for the automated install.

## Repository Layout

```
.
├── Content.Server/          Server game logic
│   └── _VS/                  Our custom server code
├── Content.Client/          Client UI and rendering
│   └── _VS/                  Our custom client code
├── Content.Shared/          Shared game logic
│   └── _VS/                  Our custom shared code
├── Content.Tests/           Unit tests
├── Content.IntegrationTests/ Integration tests
├── Content.YAMLLinter/      YAML prototype validator
├── Resources/
│   ├── Prototypes/_VS/       Our entity prototypes (YAML)
│   ├── Locale/en-US/_VS/     Our localization
│   ├── Textures/_VS/         Our sprites
│   └── Audio/_VS/            Our sounds
├── RobustToolbox/           Engine submodule (don't modify)
├── .claude/                 AI-assisted development harness
│   ├── skills/              Pipeline skills (orient, spec, impl, etc.)
│   └── settings.json        Hook configuration
├── hooks/                   Hook scripts (session, lint, commit checks)
├── docs/                    Documentation
├── CLAUDE.md                Project conventions
├── CONTRIBUTING.md          Contribution guidelines
└── LEGAL.md                 Licensing details
```

## Common Commands

### Build
```bash
dotnet build                                  # debug build
dotnet build --configuration DebugOpt         # CI-equivalent optimized debug
dotnet build --configuration Release          # production build
```

### Test
```bash
dotnet test Content.Tests --no-build                  # unit tests
dotnet test Content.IntegrationTests --no-build       # integration tests
dotnet run --project Content.YAMLLinter               # validate YAML prototypes
```

### Full quality gate (run before commits / merges)
```bash
dotnet build --configuration DebugOpt \
  && dotnet test Content.Tests --no-build --configuration DebugOpt \
  && dotnet test Content.IntegrationTests --no-build --configuration DebugOpt \
  && dotnet run --project Content.YAMLLinter \
  && dotnet format --verify-no-changes
```

### Format code
```bash
dotnet format                # format everything
dotnet format --include Content.Server/_VS/**/*.cs    # format specific files
```

### Package for distribution
```bash
dotnet build Content.Packaging -c Release
dotnet run --project Content.Packaging server --hybrid-acz --platform linux-x64
# Output in ./release/
```

## Upstream Sync

We track Delta-V upstream. Periodic merges:

```bash
git fetch upstream
git log --oneline upstream/master -10    # review incoming
git merge upstream/master
# resolve conflicts: always keep _VS code, merge upstream carefully
dotnet build && dotnet test Content.Tests --no-build
git push
```

Conflict resolution rules:
- `_VS/` files — keep ours
- `_DV/` files — take theirs (upstream Delta-V)
- Upstream files we modified — merge carefully, preserve our `// VS` annotations
- `.github/` workflows — take theirs unless we have VS overrides
- `RobustToolbox` submodule — take theirs

## Writing New Content

See `.claude/skills/prototype/SKILL.md` for YAML conventions and `.claude/skills/spec/SKILL.md` for the formal spec workflow.

Quick pattern: new C# code goes in `Content.Server/_VS/FeatureName/`, new prototypes in `Resources/Prototypes/_VS/Category/`, localization in `Resources/Locale/en-US/_VS/category.ftl`.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `RobustToolbox/` is empty | `git submodule update --init --recursive` or `python RUN_THIS.py` |
| CI fails with "RobustToolbox submodule modified" | `git checkout upstream/master RobustToolbox` |
| CRLF line ending error | `dos2unix <file>` or configure editor for LF |
| `System.DllNotFoundException: SharpFont.FT` | `sudo apt install libfreetype6` |
| libssl version mismatch | `export CLR_OPENSSL_VERSION_OVERRIDE=48` |
| Slow first build | Normal — NuGet is restoring packages (~5 min) |
| ARM64 doesn't work | Robust Toolbox < 267.0.0 lacks ARM64; use x64 emulation |

## Additional Tools

- **[RSIEdit](https://github.com/space-wizards/RSIEdit)** — GUI for editing sprite (.rsi) files. Needed if you're drawing or porting sprites.
- **[Rider](https://www.jetbrains.com/rider/)** — Recommended IDE (free for non-commercial)
- **[Robust YAML VS Code extension](https://marketplace.visualstudio.com/items?itemName=ss14.ss14-yaml)** — YAML validation for prototypes

## SS14 Reference

- [Upstream SS14 developer docs](https://docs.spacestation14.com/)
- [Delta-V Station](https://github.com/DeltaV-Station/Delta-v) (our direct upstream)
- [Space Station 14](https://github.com/space-wizards/space-station-14) (original project)
- [RobustToolbox](https://github.com/space-wizards/RobustToolbox) (engine)
