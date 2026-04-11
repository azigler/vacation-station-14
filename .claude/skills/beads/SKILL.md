---
description: Task tracking with beads-rust (br)
---

# Beads

Track tasks with `br` ([beads-rust](https://github.com/Dicklesworthstone/beads_rust)).

## Quick Reference

```bash
br list                                  # List open beads
br create -p 2 "scope: title"           # Create bead
br update <id> --description "..."       # Add description
br show <id>                             # Show details
br update <id> --status=in_progress      # Claim
br close <id>                            # Close
br sync --flush-only                     # Export to JSONL
```

## One Bead = One Commit

- Close beads BEFORE committing
- Every commit includes `Bead: <id>` trailer
- Never batch multiple closures into one commit

## Priority Levels

| Priority | Use For |
|----------|---------|
| P1 | Critical -- blockers, broken builds |
| P2 | Current work -- active features |
| P3 | Backlog -- nice-to-have |

## Bead Titles

Use scope prefixes matching the area:
```bash
br create -p 2 "cooking: add recipe system"
br create -p 1 "build: fix integration test failure"
br create -p 3 "botany: add new plant varieties"
```

## Descriptions (Required)

```bash
br update <id> --description "$(cat <<'EOF'
## Context
Why this work is needed.

## Task
What to do.

## Acceptance Criteria
- [ ] Concrete deliverable
- [ ] Tests pass
EOF
)"
```

## Agent Protocol

### At Start
```bash
br update <bead-id> --status=in_progress
```

### At Completion
```bash
br close <id>
br sync --flush-only
git add .beads/issues.jsonl
# Then commit with Bead: <id> trailer
```
