---
description: Code quality checks for C#, YAML, and assets using Roslyn + dotnet format + YAMLLinter
---

# Lint

Code quality enforcement. Layered from fastest (per-keystroke) to most thorough (full build).

## Layer 1: Per-File (automatic, via hooks)

`hooks/lint-on-write.sh` runs on every Edit/Write:
- CRLF line-ending check
- Tab detection in C# / YAML
- `dotnet format whitespace --include <file>` for C# files (~1-2s)

Auto-fixes whitespace when possible, blocks on unfixable errors.

## Layer 2: Pre-Commit (automatic, via hooks)

`hooks/pre-commit-checks.sh` runs on every `git commit`:
- Blocks `git add -A`, `--all`, or `.`
- Blocks RobustToolbox submodule staging
- CRLF check on all staged files
- `dotnet format whitespace --verify-no-changes` on staged `_VS/*.cs` files
- Warns on missing `Bead:` trailer
- Syncs and stages `.beads/issues.jsonl`

## Layer 3: Manual Deep Check

Run before branching work for review, or when debugging CI failures:

```bash
# Full format check (style + whitespace)
dotnet format --verify-no-changes

# Build with warnings visible
dotnet build --configuration DebugOpt

# Filter warnings to _VS/ code only (what we own)
dotnet build --configuration DebugOpt 2>&1 \
  | grep -E "warning|error" \
  | grep "_VS"

# YAML prototype validation
dotnet run --project Content.YAMLLinter

# CRLF check across repo
python Tools/check_crlf.py
```

## Roslyn Analyzers

SS14 has Roslyn analyzers configured in `Directory.Packages.props`. They surface
as build warnings. To run them on just the _VS/ code:

```bash
dotnet build --configuration DebugOpt 2>&1 | grep "_VS.*warning"
```

Fix all warnings in `_VS` code. Upstream warnings are inherited and not our concern.

## EditorConfig Rules (enforced)

From `.editorconfig` at repo root:
- 4-space indent for C#, 2-space for YAML/XML
- UTF-8 encoding, LF line endings
- Final newline required, trailing whitespace trimmed
- Max line length: 120

## C# Style (convention, reinforced by analyzers)

- File-scoped namespaces: `namespace Content.Server._VS.Cooking;`
- Allman braces
- `var` preferred
- Private fields: `_camelCase`, public: `PascalCase`
- Interfaces: `IPascalCase`, type params: `TPascalCase`
- Classes must be `abstract`, `static`, `sealed`, or `[Virtual]`
- `const` for unchanging values, CVars for configurable
- `TimeSpan` instead of `float` for durations
- Nullable `EntityUid?` not `EntityUid.Invalid`
- `[DataField]` on serialized component fields
- `[AutoNetworkedField]` on fields that need client sync
- `[Access(...)]` to restrict component modification to specific systems

## YAML Conventions

- 2-space indent, spaces only (never tabs)
- PascalCase entity IDs and component names
- camelCase field values
- Prototype field order: `type -> abstract -> parent -> id -> categories -> name -> suffix -> description -> components`
- Engine components (Sprite, Physics) near top
- Content components near bottom
- No empty lines between components; one empty line between prototypes

Validated by `Content.YAMLLinter`.

## Asset Validation (CI only)

- `validate-rsis.yml` — sprite sheet validation
- `validate-rgas.yml` — animation validation
- `validate_mapfiles.yml` — map schema check

## Pre-Commit Checklist

The hooks enforce most of these, but check manually if something feels off:

- [ ] `dotnet build --configuration DebugOpt` clean
- [ ] No new warnings in `_VS` code
- [ ] `dotnet format --verify-no-changes` passes
- [ ] `dotnet run --project Content.YAMLLinter` passes
- [ ] No CRLF line endings
- [ ] RobustToolbox submodule unchanged
- [ ] Localization strings added for player-visible text
- [ ] `[DataField]` on new component fields
- [ ] Bead: trailer in commit message

## Auto-fix Commands

```bash
# Fix whitespace across the repo
dotnet format whitespace

# Fix style issues (more aggressive, uses analyzers)
dotnet format style

# Fix everything
dotnet format

# Fix specific files
dotnet format --include Content.Server/_VS/Cooking/RecipeSystem.cs

# Convert CRLF to LF
find . -type f \( -name "*.cs" -o -name "*.yml" -o -name "*.ftl" \) \
  -not -path "./RobustToolbox/*" \
  -exec dos2unix {} \;
```
