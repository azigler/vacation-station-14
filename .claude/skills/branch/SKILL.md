---
description: Branching and release strategy with worktree agents
---

# Branch & Release

Work on `v0.N/descriptive-name` branches. Worktree agents merge into the branch.
Only the orchestrator merges to `main`.

## Branch Lifecycle

### 1. Baseline Check
```bash
git checkout main
dotnet build --configuration DebugOpt
```
Do not branch from a broken baseline.

### 2. Create Branch
```bash
git checkout -b v0.N/descriptive-name
git push -u origin v0.N/descriptive-name
```

### 3. Work on Branch
Dispatch agents with: `Merge target: v0.N/descriptive-name`

### 4. Quality Gate
```bash
dotnet build --configuration DebugOpt \
  && dotnet test Content.Tests --no-build --configuration DebugOpt \
  && dotnet test Content.IntegrationTests --no-build --configuration DebugOpt \
  && dotnet run --project Content.YAMLLinter
```

### 5. Merge + Tag
```bash
git checkout main
git merge v0.N/descriptive-name --no-edit
git tag -a v0.N.R -m "description"
git push origin main --tags
```

### 6. GitHub Release
```bash
gh release create v0.N.R --title "title" --notes "..."
```

### 7. Cleanup
```bash
git branch -d v0.N/descriptive-name
git push origin --delete v0.N/descriptive-name
```

## Naming

| Thing | Pattern | Example |
|-------|---------|---------|
| Branch | `v0.N/descriptive-name` | `v0.1/persistence-system` |
| Tag | `v0.N.R` | `v0.1.1` |
| Worktree | `worktree-agent-XXXX` | merges into branch |
