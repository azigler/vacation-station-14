---
description: Write specifications. Prefer bead descriptions; escalate to docs/specs/ only for large formal specs.
---

# Spec

**Beads are the primary spec artifact.** A well-structured bead description
(Context, Task, Acceptance Criteria) functions as a spec for most work. Escalate
to a formal `docs/specs/NN-name.md` only when the spec is too large to fit
comfortably in a bead or when multiple implementations reference it.

## Where Specs Live

| Location | Use for |
|----------|---------|
| **Bead description** | Default — single-feature specs, implementation plans, acceptance criteria |
| **`docs/specs/NN-name.md`** | Cross-cutting systems, multi-bead features, anything referenced repeatedly |
| **`docs/` (top-level)** | Stable human+AI reference (NETWORKING, HOSTING, DEVELOPMENT, OPERATIONS) |
| **Never `.claude/refs/`** | Don't use this pattern — keep docs discoverable in `docs/` |

## Bead Types

Bead titles use a scope prefix. Choose by primary output:

| Prefix | Output | Example |
|--------|--------|---------|
| `research:` | Knowledge (captured in bead description or a docs/ page) | `research: how does HardLight persist state across rounds` |
| `spec:` | A `docs/specs/NN-name.md` formal document | `spec: player state serialization to postgres` |
| `impl:` | Code (implementation matching a bead's or spec's criteria) | `impl: cryosleep hook for player state save` |
| `docs:` | A docs/*.md page | `docs: networking guide with caddy` |
| `ops:` | Operational/deployment work | `ops: watchdog setup from day 1` |
| `test:` | Tests for existing or upcoming implementation | `test: spec 03 recipe system unit tests` |
| `fix:` | Bug fixes | `fix: null ref when player reconnects mid-round` |

Beads often transition: a `research:` bead produces findings that feed into
a `spec:` bead, which is then realized by one or more `impl:` beads. Rename as
scope shifts — don't create a new bead for the same thread of work.

## Bead-as-Spec Structure

Every non-trivial bead description should have three sections:

```markdown
## Context
Why this work matters, what preceded it, what constraints apply.
Link or reference any prior beads, specs, or research.

## Task
Concrete description of what to build or decide. Name the files/modules
that will be touched. Call out open questions inline if any.

## Acceptance Criteria
- [ ] Specific, testable deliverable
- [ ] Another specific, testable deliverable
- [ ] Quality gates (tests pass, lint clean, docs updated)
```

For larger scope beads, add:

```markdown
## Dependencies
Other beads, specs, or external systems this depends on.

## Scope
What's in scope vs explicitly out of scope.
```

## When to Escalate to `docs/specs/NN-name.md`

Escalate when:
- Spec is referenced by multiple implementation beads
- Spec covers a subsystem with API contracts between components
- Spec includes more than ~10 test cases
- You're writing multi-page design rationale

Formal spec structure:

```markdown
# Spec NN: [Subsystem Name]

## 1. Overview
- What this subsystem does
- Role in the game
- Dependencies on other systems
- Out of scope

### 1.1 Sources
| Source | Insight |
|--------|---------|

## 2. Current State
Baseline: what exists today.

## 3. Changes
Change / Rationale pairs.

## 4. Formal Specification
Components (with [DataField]), EntitySystems (event handlers),
prototype YAML, network messages.

## 5. Test Cases
TEST: name
INPUT: action
EXPECTED: result
RATIONALE: what this tests

## 6. Implementation Notes
Which _VS/ directories, performance notes, split decisions.

## 7. Open Questions
## 8. Future Considerations
```

Number specs sequentially (`01-cooking-system.md`, `02-persistence.md`).

## Writing Specs for SS14 Systems

Ground every spec in SS14's ECS architecture:

- **Components** are pure data with `[DataField]` attributes. Show C# sketch.
- **Systems** subscribe to events. Show which events and handler signatures.
- **Prototypes** are YAML. Show complete prototype examples.
- **Networking**: specify `[AutoNetworkedField]` vs server-only fields.
- **Localization**: call out strings needing `.ftl` entries in `Resources/Locale/en-US/_VS/`.
- **Client/Server/Shared split**: specify where each piece lives.

## Self-Review Before Closing

Beads:
- [ ] Context explains why, not just what
- [ ] Task is concrete enough for someone else to execute
- [ ] Acceptance Criteria are verifiable (not vague like "works well")
- [ ] Dependencies / blocking work is named

Formal specs:
- [ ] All components have `[DataField]` annotations shown
- [ ] Client/Server/Shared split is specified
- [ ] At least 10 test cases with INPUT/EXPECTED/RATIONALE
- [ ] Prototype YAML examples included
- [ ] Localization strings identified

## Output

### Bead-only specs
The bead description is the spec. Close when all acceptance criteria are met.

### Formal specs
Write to `docs/specs/NN-name.md`. Commit with:
```
:page_facing_up: spec: [subsystem name]

Bead: <bead-id>
```

Then create downstream `impl:` beads that reference `docs/specs/NN-name.md` in
their Context.
