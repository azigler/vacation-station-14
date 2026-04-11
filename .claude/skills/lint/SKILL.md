---
description: Code quality checks for C#, YAML, and assets
---

# Lint

Code quality enforcement for Vacation Station 14.

## C# Code Quality

### Build Warnings
```bash
dotnet build --configuration DebugOpt 2>&1 | grep -E "warning|error"
```
Fix all warnings in `_VS` code. Upstream warnings are inherited and not our concern.

### EditorConfig Rules (enforced)
- 4-space indent for C#
- 2-space indent for YAML, XML, csproj
- UTF-8 encoding
- LF line endings (CRLF rejected by CI)
- Final newline required
- Trailing whitespace trimmed
- Max line length: 120

### C# Style (enforced by convention)
- File-scoped namespaces: `namespace Content.Server._VS.Cooking;`
- Allman braces
- `var` preferred
- Private fields: `_camelCase`
- Public: `PascalCase`
- Interfaces: `IPascalCase`
- Classes must be `abstract`, `static`, `sealed`, or `[Virtual]`
- `const` for unchanging values
- `TimeSpan` instead of `float` for durations
- Nullable `EntityUid?` not `EntityUid.Invalid`

## YAML Validation

```bash
dotnet run --project Content.YAMLLinter
```

### YAML Conventions
- 2-space indent
- PascalCase for entity IDs and component names
- camelCase for field values
- Prototype field order: type, abstract, parent, id, categories, name, suffix, description, components
- Engine components near top, content components near bottom
- No empty lines between components; one empty line between prototypes

## Asset Validation

CI runs:
- `validate-rsis.yml` -- sprite sheet validation
- `validate-rgas.yml` -- animation validation
- `validate_mapfiles.yml` -- map file schema check

## CRLF Check

```bash
python Tools/check_crlf.py
```

CI rejects any files with CRLF line endings.

## Pre-Commit Checklist

- [ ] `dotnet build` clean
- [ ] No new warnings in `_VS` code
- [ ] YAML linter passes
- [ ] No CRLF line endings
- [ ] RobustToolbox submodule unchanged
