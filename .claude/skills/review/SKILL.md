---
description: Walk through open questions, conflicts, and dependencies for decision-making
---

# Review Workflow

Guide the user through reviewable items needing decisions before implementation.

## Item Types

1. **Open Questions (OQs)** -- Design questions needing a decision
2. **Cross-Spec Conflicts** -- Inconsistencies between specs
3. **Cross-Spec Dependencies** -- Interface agreements needing confirmation

## Presenting Items

### Open Questions
```
### OQ-NN: [Title]
**Priority:** P1/P2/P3
**Source:** Spec NN, Section X
**Affects:** [systems]

**Question:** [verbatim]
**Expert Analysis:** [pros/cons of options]
**Recommendation:** [ACCEPT / MODIFY / DEFER]
```

### Conflicts
```
### Conflict #N: [Title]
**Specs involved:** Spec NN vs. Spec MM
**The inconsistency:** [description]
**Recommended resolution:** [which spec changes]
```

## Recording Decisions

Update the decisions document with:
- `**Status: DECIDED (YYYY-MM-DD)**`
- `**Answer:** [decision]`
- `**Rationale:** [why]`
- `**Spec update needed:** [if applicable]`

Do NOT modify specs during review. Record what needs updating.

## Batch Mode

- `review all P1` -- all priority 1 questions
- `review all` -- everything, P1 first
- Present one at a time, ask "Continue?" between each

## Implementation Readiness Report

When all P1 OQs are decided and conflicts resolved:

```markdown
## Implementation Readiness Report

**P1 OQs decided:** N/N
**Conflicts resolved:** N/N
**Dependencies confirmed:** N/N

### Recommended Implementation Order
[based on dependencies]

### Spec Updates Required
[list by spec number]
```

This is the handoff from `/review` to `/impl`.
