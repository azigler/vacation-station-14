---
description: Maintainer playbook for agent-era OSS — PR triage, fix-merge discipline, and attribution rules for a solo human + AI maintainer.
---

# Vibe Maintainer

Playbook for maintaining VS14 under the agent-era new normal: one human
maintainer plus AI assistance, no volunteer review team, AI-assisted
contributors submitting higher-velocity and lower-effort PRs, and a
community where rejection raises the odds of a downstream fork.

Pairs with:
- `vs-2sr` — `CONTRIBUTING.md` (contributor-facing hygiene rules reflecting this skill)
- `vs-f0l` — scheduled PR triage workflow + auto-merge policy (CI automates the easy-win branch of this tree)
- `/commit`, `/upstream-sync`, `/review`, `/orchestrator`

## Philosophy

1. **Absorb by default, reject only on principle.** Every rejection is a
   fork invitation. If the idea is reasonable and the code is fixable,
   fix it and merge with attribution preserved.
2. **Preserve attribution.** Git author, `Co-Authored-By:`, and `:cl:`
   changelog entries all name the original contributor even when we
   rewrite their diff substantially.
3. **Optimize for throughput, not per-PR perfection.** Follow-up commits
   are cheap; bounced PRs are expensive.
4. **Solo + AI is the operating assumption.** Do not design workflows
   that assume a review committee. Agent assistance for triage and
   first-pass review is expected; human judgment is reserved for the
   ambiguous subset.
5. **Reject when you mean it.** Rejection should be a conscious, rare,
   explained act — not a default.

## PR triage tiers

At first read, bin each incoming PR into one of three tiers. The
automation in `vs-f0l` will apply labels (`triage/easy-win`,
`triage/fix-merge`, `triage/deeper-look`) and post a `triage-summary`
comment; use it as a starting point, not a verdict.

| Tier | Description | Default action |
|---|---|---|
| **Easy win** | Targeted fix, doc tweak, dep bump, clearly-right change from a known-good author | Review, merge |
| **Fix-merge candidate** | Good idea, minor issues (lint, naming, missed annotation, small bug) | Pull locally, fix, merge with attribution |
| **Needs deeper look** | Ambiguous in scope, substance, or design | Run the decision tree below |

## Decision tree (needs-deeper-look PRs)

Pick exactly one outcome. "Request changes" is last resort.

1. **Easy win** — reclassify; merge.
2. **Merge** — clean and ready; merge.
3. **Merge + follow-up** — merge now, open a bead for the minor fixup we
   will ship in a later commit.
4. **Fix-merge** — pull locally, resolve issues, merge with attribution
   preserved (see `Fix-merge mechanics`).
5. **Cherry-pick** — take the N good commits; politely discard the rest.
6. **Split-merge** — decompose a multi-concern PR into separate commits
   with attribution; merge each independently.
7. **Redesign** — the problem is worth solving but their design is
   wrong. Close with an explanation and file a bead to solve it our way.
8. **Retire** — the PR is obsolete or superseded. Thank + close.
9. **Reject** — the change fails a cost/benefit threshold. Polite
   decline; explain briefly.
10. **Request changes** — last resort. Only when the contributor
    specifically wants ownership and the change is one they can
    reasonably finish. Document why a fix-merge was not appropriate.

## Reading automation output

`vs-f0l` workflows (aspirational — not yet implemented) will attach:

- **Labels** — `triage/easy-win`, `triage/fix-merge`,
  `triage/deeper-look`, plus risk flags (`risk/security`,
  `risk/cross-fork`, `risk/large-diff`).
- **Triage summary comment** — an agent-generated first-pass read of
  the diff, proposed tier, and any risk checklist hits.

Treat these as a pre-sorted inbox, not a decision. Re-read the diff
before clicking merge. The agent's summary is wrong often enough that
rubber-stamping it is an anti-pattern.

## Fix-merge mechanics

Preferred over "request changes" whenever the contributor's work is
salvageable.

```bash
# Fetch the PR head
git fetch origin pull/<N>/head:pr-<N>
git checkout pr-<N>

# Apply surgical fixes — smallest possible diffs
# Stage your fix commits with attribution intact:
git commit --author="Original Author <email@example.com>" -m "..."
# OR keep your own authorship and add a trailer:
#   Co-Authored-By: Original Author <email@example.com>

# Rebase onto main
git rebase main

# Merge (squash or rebase-merge depending on PR shape)
# Close the original PR with a thank-you summarizing what we fixed.
```

When squashing, the final commit subject should reference the PR:
`:sparkles: cooking: add pasta recipe (from #42)`. Preserve the original
author as the primary author of the squashed commit; add
`Co-Authored-By:` for our conflict-resolution. The `:cl:` changelog
block names the original author, not us.

## Attribution discipline

Non-negotiable for any externally-originated commit reaching `main`:

- **Git author** preserved on cherry-picked commits.
- **`Co-Authored-By:`** trailer when we did conflict resolution or fix-merge edits.
- **`:cl:`** changelog block names the original author.
- **Subject reference** — `(from #<pr-number>)` for external-PR-origin
  commits, `(from <upstream>@<sha>)` for fork cherry-picks.

This mirrors the `LEGAL.md` + `docs/upstream-sync.md` rules for
`_<FORK>/` subsystems: the license chain must be reconstructable from
`git log --follow`. See `/upstream-sync` for the full cherry-pick
workflow when pulling from Delta-V, Frontier, Einstein, Starlight, or
HardLight.

## Hygiene rules we enforce on contributors

Violations are typically fix-merge fodder, not rejection fuel:

- **Namespace isolation** — `_VS/` stays separate from `_DV/`, `_NF/`,
  etc. No cross-fork edits in a single commit.
- **Annotation markers** — `// VS`, `// DV`, `// NF` comments on
  modifications to upstream-owned files (see `CLAUDE.md`).
- **One concern per PR** — prefer split-merge if violated.
- **Rebased onto current `main`** before submission.
- **Minimal diffs** — no gratuitous renames, reformats, or whitespace churn.
- **`:cl:` changelog block** for player-facing changes.
- **Bead reference** for non-trivial changes.
- **No drafts left open** — auto-close stale drafts (handled by
  `vs-f0l` automation).

## Security checklist (AI-generated PRs)

Run this quickly on every non-trivial PR. Any hit escalates to human:

- New secrets, tokens, or credentials in the diff?
- New network endpoints, especially outbound?
- New dependencies? Pinned to specific versions?
- Auth, identity, or admin-path changes?
- Base64 blobs or obfuscated strings without obvious purpose?
- Build or CI config changes that could exfiltrate state?

## When to escalate to human

Even as an orchestrator with AI review, escalate before merging if:

- Substantial architectural change.
- Any security-checklist hit.
- Controversial design — PR comments disagree with our stated direction.
- Unknown contributor with a sweeping diff.
- Touches `_DV/`, `_NF/`, or other `_<FORK>/` code in a way that
  conflicts with upstream-sync expectations.
- License-sensitive change (touches `LEGAL.md`, `LICENSE*`, boundary
  commit annotations, or `attributions.yml`).

## Close vs hold

- **Close** when the decision is final: rejected, retired, superseded,
  or fix-merged (close original after landing our version). Always
  leave a one-paragraph explanation.
- **Hold** when waiting on the contributor, upstream, or our own
  unshipped work. Apply a `status/blocked-*` label and a comment
  naming the blocker. Re-sweep holds weekly.

Do not leave a PR open without a state. Every PR has a tier, a
decision, or a named blocker.

## Communication tone

- Thank the contributor in every reply — merged, fix-merged, or rejected.
- Be specific about what changed when we fix-merged. Link the landed commit.
- Explain rejections in one paragraph. No hand-waving, no templated
  brush-offs.
- Never imply the contributor should have known better. Our hygiene
  rules are documented (`CONTRIBUTING.md`); point at the doc rather
  than lecturing.

## Self-check before merging

- [ ] Attribution preserved (author + co-author + `:cl:`)?
- [ ] Security checklist clean?
- [ ] Namespace isolation intact (`_VS/` vs `_<FORK>/`)?
- [ ] Annotation markers present on upstream-file edits?
- [ ] Bead referenced (for non-trivial changes)?
- [ ] Rebased onto current `main`?
- [ ] Changelog entry in the right spot?
