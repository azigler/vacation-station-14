---
description: Sync from Delta-V upstream, merge changes, resolve conflicts
---

# Upstream Sync

Merge changes from Delta-V's master branch into our fork.

## Prerequisites

```bash
git remote -v  # verify 'upstream' points to DeltaV-Station/Delta-v
```

If missing: `git remote add upstream https://github.com/DeltaV-Station/Delta-v.git`

## Sync Procedure

### Step 1: Fetch

```bash
git fetch upstream
git log --oneline upstream/master -10  # review incoming changes
```

### Step 2: Merge

```bash
git checkout main
git merge upstream/master
```

### Step 3: Resolve Conflicts

Conflict resolution rules:
- **`_VS/` files**: Always keep ours. These are our custom code.
- **`_DV/` files**: Always take theirs. These are Delta-V's code.
- **Upstream files we modified**: Merge carefully. Check `// VS` annotations
  to understand what we changed and why. Reapply our changes on top of theirs.
- **`.github/` workflows**: Take theirs unless we have VS-specific overrides.
- **`RobustToolbox` submodule**: Take theirs (we track their engine version).

### Step 4: Verify

```bash
dotnet build --configuration DebugOpt
dotnet test Content.Tests --no-build --configuration DebugOpt
dotnet test Content.IntegrationTests --no-build --configuration DebugOpt
dotnet run --project Content.YAMLLinter
```

### Step 5: Commit and Push

If the merge was clean, git auto-commits. If conflicts were resolved:

```bash
git add <resolved-files>
git commit  # auto-generated merge message is fine
git push
```

## Early Merges

For urgent upstream fixes, cherry-pick specific PRs instead of full merge:

```bash
git fetch upstream
git cherry-pick <commit-hash>
```

Cherry-picked code doesn't need `// VS` annotations since it's unmodified upstream.

## Frequency

Sync periodically (weekly or monthly) depending on upstream activity. Large
syncs are harder to resolve -- more frequent is better.
