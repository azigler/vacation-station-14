---
description: Task tracking with beads-rust (br)
---

# Beads

Track tasks with `br` ([beads-rust](https://github.com/Dicklesworthstone/beads_rust)).

## Quick Reference

```bash
br list                                  # List open beads
br create -p 2 "scope: title"            # Create bead
br update <id> --description=...         # Add description (use = form, see gotcha)
br show <id>                             # Show details (read description + deps)
br update <id> --status=in_progress      # Claim
br close <id>                            # Close
br ready                                 # Show unblocked work (critical!)
br blocked                               # Show blocked work (visualize wait states)
br dep tree <id>                         # Dependency subtree rooted at bead
br dep add A B --type blocks             # A waits on B
br dep add A B --type parent-child       # A is child of epic B
br epic status                           # Epic-level progress summary
br sync --flush-only                     # Export to JSONL
```

## Creating epics + children

`br` supports hierarchical decomposition. Large tasks decompose into an
**epic** containing multiple child **tasks**, with dependencies between
children encoding execution order. This removes the need for giant
instructional prompts — the dependency graph + each bead's description
carry the execution plan.

### Create an epic
```bash
br create --type epic -p 1 "epic: big-thing"
# → creates vs-abc (say)
```

### Create children
```bash
br create --type task --parent vs-abc -p 1 "phase 1: do foo"
# → creates vs-abc.1 (hierarchical ID, automatic)
br create --type task --parent vs-abc -p 1 "phase 2: do bar"
# → creates vs-abc.2
```

Children under an epic are named `<epic-id>.<N>`. This naming is
meaningful to humans scanning `br list` — children of `vs-abc` are
visually grouped by shared prefix.

### Chain children with `blocks` deps
```bash
br dep add vs-abc.2 vs-abc.1 --type blocks   # phase 2 blocks on phase 1
br dep add vs-abc.3 vs-abc.2 --type blocks   # etc.
```

After this, `br ready` surfaces only `vs-abc.1` among the epic's
children. When it closes, `vs-abc.2` becomes ready. Automatic ordering.

### Cross-cutting deps
Independent beads can also depend on specific phases:
```bash
br dep add vs-other vs-abc.1 --type blocks
```
`vs-other` is now gated on `vs-abc.1` completing.

### Agent onboarding via epics
The modern pattern for handing a large plan to a new session:
1. Make an epic (`br create --type epic`).
2. Create phase children with full procedures in their descriptions.
3. Chain `blocks` deps.
4. Put agent-facing instructions (read-skills-directly, stop-gates,
   etc.) in the epic's description.
5. Tell the agent: "`br show <epic-id>`, then `br ready`, execute each
   bead in order. Stop at the gate noted in the epic."

The agent starts with `br show <epic>`, sees the instructions, runs
`br ready`, gets its first task, reads its description, executes, closes,
repeats. No separate instructional prompt needed.

## Quick-capture vs full-create

```bash
br q -p 2 "short title only"       # Fastest; prints ID only; no --type/--parent
br create ...                      # Full control; use this when you need --type,
                                   # --parent, --deps, etc.
```

`br q` is for rapid brain-dump; it doesn't accept `--parent` or `--type`.
Use `br create` for anything structural.

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

## Gotcha: values starting with `- ` (dash-space)

When a flag value begins with `- ` (e.g., a markdown bullet list), `br`'s
CLI parser interprets the dash as the start of another flag and errors
out. Use the **equals form** to pass it as a literal value:

```bash
# FAILS (parser sees `- [ ] Item` and looks for a `- [ ]` flag):
br update vs-abc --acceptance-criteria "$(cat <<'EOF'
- [ ] Item 1
- [ ] Item 2
EOF
)"

# WORKS (equals-form isolates the value):
br update vs-abc --acceptance-criteria="$(cat <<'EOF'
- [ ] Item 1
- [ ] Item 2
EOF
)"
```

Applies to any `br update` flag whose value may start with a dash:
`--title`, `--description`, `--design`, `--acceptance-criteria`, `--notes`.
When in doubt, use the `=` form — it costs nothing and prevents the
error class entirely.

Title with a leading `- ` is rare but possible; error message is:
```
error: unexpected argument '- ' found
  tip: to pass '- ' as a value, use '-- - '
```

## Fields separate from description

`br` stores `description` and `acceptance_criteria` as DISTINCT fields.
Embedding an `## Acceptance` heading inside `--description` populates
the description, NOT the structured `acceptance_criteria` field. If the
bead tooling queries that field (downstream lint, reports), the two
aren't the same. For canonical acceptance criteria, use the dedicated
flag:

```bash
br update <id> --acceptance-criteria="$(cat <<'EOF'
- Item 1
- Item 2
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
