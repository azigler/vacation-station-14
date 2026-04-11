---
description: Orchestrator pattern for delegating to worktree subagents
---

# Orchestrator

Coordinate work by creating beads, dispatching subagents, and merging results.

## Core Principle

Delegate implementation to **worktree subagents**:
```
subagent_type: "subagent"
isolation: "worktree"
```

Built-in types (`Explore`, `Plan`) are for read-only research only.

## Bead Lifecycle

Orchestrator owns create, claim, close. Subagents only reference the ID.

### Create and Assign
```bash
br create -p 2 "scope: title"
br update <id> --status=in_progress
```

### After Subagent Completes
```bash
git merge worktree-agent-XXXX --no-edit
git merge-base --is-ancestor worktree-agent-XXXX HEAD

br close <bead-id>
git add .beads/issues.jsonl
git commit -m ":card_file_box: beads: close <bead-id>"

git worktree remove --force .claude/worktrees/agent-XXXX
git branch -D worktree-agent-XXXX
git push origin --delete worktree-agent-XXXX 2>/dev/null || true
```

## Subagent Prompt Template

```
Your bead is `<bead-id>`. Include `Bead: <bead-id>` in your commit trailer.

## Task
[Clear description]

## Scope
- Module: [which _VS module]
- Files: [to create/modify]

## Acceptance Criteria
- [ ] [Specific criterion]
- [ ] dotnet build clean
- [ ] Tests pass

## Pre-Commit
dotnet build && dotnet test Content.Tests --no-build
```

## Wave Ordering: Test -> Merge -> Impl

1. Dispatch test agents (parallel OK)
2. Wait for completion
3. **Merge all test worktrees**
4. **Clean up all test worktrees immediately**
5. **Push branch**
6. Dispatch impl agents
7. Merge, quality gate, release

## Parallel Agents

```bash
# After parallel agents complete:
git merge worktree-agent-AAA --no-edit
git merge worktree-agent-BBB --no-edit

br close <id-a> && br close <id-b>
git add .beads/issues.jsonl
git commit -m ":card_file_box: beads: close <id-a>, <id-b>"

git worktree remove --force .claude/worktrees/agent-AAA
git worktree remove --force .claude/worktrees/agent-BBB
git branch -D worktree-agent-AAA worktree-agent-BBB
```
