---
description: Session entrypoint -- discover state, classify work, route to sub-skill
---

# Orient

Entry point for every session. Discovers current state, classifies remaining
work, and routes to the appropriate skill.

## Step 1: Read Foundation

1. `CLAUDE.md` — project conventions
2. **Every skill under `.claude/skills/*/SKILL.md` — read all of them
   yourself, DIRECTLY, in this session.** Do NOT dispatch the `Explore`
   subagent (or any subagent) to summarize them. Load each skill's
   content into this conversation's context directly — summaries lose
   the load-bearing details. Skills are short; read them all. This is
   critical: agent behavior on this repo depends on understanding every
   skill's exact rules.
3. Any active plan or spec files
4. `docs/upstream-sync.md` if present — lists every upstream we track
   and our mode (submodule / cherry-pick / deploy-as-is)

## Step 2: Discover Live State

```bash
git log --oneline -5
git branch -a | grep -v worktree
br list
git status --short
```

Determine: current branch, open beads, dirty files, recent work.

## Step 3: Classify Work

| Domain | Skill | When |
|--------|-------|------|
| **Spec** | `/spec` | Writing or amending a specification |
| **Review** | `/review` | Deciding open questions |
| **Test** | `/test` | Writing tests before implementation |
| **Impl** | `/impl` | Building code until tests pass |
| **Branch** | `/branch` | Branching, merging, tagging |
| **Build** | `/build` | Building and verifying the project |
| **Upstream** | `/upstream-sync` | Merging Delta-V updates |

## Step 4: Check Blockers

1. Build broken? -> `/build` first
2. Open P1 questions? -> `/review` first
3. Dirty git state? -> Clean up first
4. Interrupted beads? -> Assess whether to resume or close

## Step 5: Present and Route

```
## Orientation Report

**Branch**: main
**Open beads**: [list or none]
**Build status**: [passing / unknown / broken]
**Skill domain**: [spec / review / test / impl / build / upstream-sync]
**Blockers**: [none / list]

**Recommended action**: [what to do next]
```

## Post-Compaction Recovery

1. Do NOT immediately create branches or beads. Orient first.
2. Read any active plan or spec files.
3. Check what's done via git history. Don't redo completed work.
4. Present findings before taking action.
