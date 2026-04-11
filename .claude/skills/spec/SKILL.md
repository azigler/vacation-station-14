---
description: Write formal specification documents for SS14 systems and features
---

# Spec Creation Workflow

Write a complete specification document for a system or feature.

## Inputs

1. **Spec name** -- what you're specifying
2. **Bead ID** -- include as `Bead: <id>` in commit trailers
3. **Scope** -- what it covers and does NOT cover

## Step 1: Load Context

1. `CLAUDE.md` -- project conventions
2. Existing specs in `specs/`
3. Related SS14 source code (components, systems, prototypes)
4. Upstream SS14 docs if relevant

## Step 2: Understand Baseline

What already exists? Read the current implementation code, prototypes, and any
related systems. Document the current state.

## Step 3: Write the Spec

### Structure

```markdown
# Spec: [System Name]

## 1. Overview
- What this system does
- Role in the game
- Dependencies on other systems
- What is NOT covered

### 1.1 Sources
| Source | Insight |
|--------|---------|

## 2. Current State
- What exists today
- Key components, systems, prototypes
- References to existing code

## 3. Changes
- **Change:** what is different
- **Rationale:** why

## 4. Formal Specification
- Components with [DataField] annotations
- EntitySystems with event subscriptions
- Prototype YAML structures
- Network messages if applicable

## 5. Test Cases
TEST: [name]
INPUT: [action or API call]
EXPECTED: [result]
RATIONALE: [what this tests]

## 6. Implementation Notes
- Which _VS/ directories to use
- Performance considerations
- Client/Server/Shared split decisions

## 7. Open Questions
## 8. Future Considerations
```

### SS14-Specific Guidelines

- **Components** are pure data with `[DataField]` attributes. Show the C# sketch.
- **Systems** subscribe to events. Show which events and the handler signatures.
- **Prototypes** are YAML. Show complete prototype examples.
- **Networking**: specify what's `[AutoNetworkedField]` vs server-only.
- **Localization**: note which strings need `.ftl` entries.

## Step 4: Self-Review

- [ ] All components have `[DataField]` annotations shown
- [ ] Client/Server/Shared split is specified
- [ ] At least 10 test cases
- [ ] Prototype YAML examples included
- [ ] Localization strings identified

## Output

Write to `specs/[NN]-[kebab-case-name].md`. Commit with:
```
:page_facing_up: spec: [system name]

Bead: <bead-id>
```
