---
description: Build the SS14 project and diagnose failures
---

# Build

Build the project and report results.

## First-Time Setup

```bash
python RUN_THIS.py    # initializes RobustToolbox submodule
```

If `RobustToolbox/` is empty, the submodule isn't initialized. Run the above
or `git submodule update --init --recursive`.

## Build Commands

```bash
# Standard build
dotnet build

# Optimized debug build (used by CI)
dotnet build --configuration DebugOpt

# Release build
dotnet build --configuration Release
```

## Test Commands

```bash
# Unit tests
dotnet test Content.Tests --no-build

# Integration tests
dotnet test Content.IntegrationTests --no-build

# YAML prototype validation
dotnet run --project Content.YAMLLinter
```

## Full Quality Gate

Run all checks before merging:

```bash
dotnet build --configuration DebugOpt \
  && dotnet test Content.Tests --no-build --configuration DebugOpt \
  && dotnet test Content.IntegrationTests --no-build --configuration DebugOpt \
  && dotnet run --project Content.YAMLLinter
```

## Common Build Issues

| Issue | Fix |
|-------|-----|
| RobustToolbox empty | `git submodule update --init --recursive` |
| RobustToolbox changed in diff | `git checkout upstream/master RobustToolbox` |
| Missing .NET SDK | Install .NET 10 SDK |
| CRLF line endings | Convert to LF: `git config core.autocrlf input` |
| NuGet restore failure | `dotnet restore` or check network |

## CI Workflows

The repo has GitHub Actions for:
- `build-test-debug.yml` -- builds DebugOpt + runs tests
- `yaml-linter.yml` -- validates YAML prototypes
- `check-crlf.yml` -- rejects CRLF line endings
- `no-submodule-update.yml` -- fails PRs that modify RobustToolbox submodule
- `validate_mapfiles.yml` -- validates map YAML
