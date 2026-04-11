---
description: Orchestrator-level implementation planning for test-first development
---

# Implementation Orchestrator

Plan and dispatch implementation work via beads and subagents.

## Flow

```
/review (all P1 decided) -> Implementation Readiness Report
  -> /branch (create version branch)
  -> /impl plan (scope the work)
  -> /test (write tests on branch)
  -> merge test agents, clean up
  -> /impl dispatch (build until tests pass)
  -> merge impl agents
  -> quality gate
  -> /branch merge + tag
```

## Step 1: Plan Scope

```
Scope: [Name]
Branch: v0.N/descriptive-name
Specs: [list]
Depends on: [prior work]
```

## Step 2: Create Beads

### Test beads first:
```bash
br create -p 2 "tests: spec NN [system]"
```

### Then implementation beads:
```bash
br create -p 2 "impl: [module]"
```

## Step 3: Dispatch

### Test agents
```
Your bead is `<id>`. Include `Bead: <id>` in your commit trailer.
Merge target: v0.N/descriptive-name (NOT main).

Follow /test skill. Write ONLY test files to Content.Tests/_VS/ or
Content.IntegrationTests/Tests/_VS/.
```

### Implementation agents
```
Your bead is `<id>`. Include `Bead: <id>` in your commit trailer.
Merge target: v0.N/descriptive-name (NOT main).

Make all tests pass. Follow spec Section 4 and 6.

Pre-commit: dotnet build && dotnet test Content.Tests --no-build
```

## Step 4: Wave Ordering (CRITICAL)

1. Dispatch test agents (parallel OK)
2. Wait for completion
3. **Merge all test worktrees into version branch**
4. **Clean up all test worktrees immediately**
5. **Push the version branch**
6. ONLY THEN dispatch impl agents
7. Merge impl agents
8. Quality gate

## Quality Gate

Before merging branch to main:

```bash
dotnet build --configuration DebugOpt
dotnet test Content.Tests --no-build --configuration DebugOpt
dotnet test Content.IntegrationTests --no-build --configuration DebugOpt
dotnet run --project Content.YAMLLinter
```

If any check fails, create fix beads before merging.

## Cross-Cutting Requirements

Include in every implementation agent prompt:
- All tests pass
- Build clean (no warnings in _VS code)
- `[DataField]` on all serialized component fields
- `[AutoNetworkedField]` on fields that need client sync
- Localization strings in `Resources/Locale/en-US/_VS/`
- Doc comments on public API
