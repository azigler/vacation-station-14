# Contributing to Vacation Station 14

Thanks for considering a contribution. VS14 is a solo-maintained,
AI-assisted SS14 derivative: the base is pure SS14, sibling-fork features
land as attributed cherry-picks in `_<FORK>/` subsystems, and new content
lives under `_VS/`. This document covers the hygiene rules that keep that
model reviewable.

For the legal picture (license boundary, per-upstream attribution,
per-service compliance), see [LEGAL.md](LEGAL.md). For the architectural
overview, see [README.md](README.md). For the dev environment, see
[`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

## Posture

VS14 is maintained in a "vibe-maintainer" mode:

- **AI-assisted PRs are welcome.** Flag them in the PR body for
  transparency; it is not a gate. Most forks treat AI assistance as a
  red flag, we treat it as a tool.
- **We fix-merge rather than request changes** when practical. If your
  PR has a good core with rough edges, we are likely to absorb it and
  smooth the edges ourselves, preserving your authorship in git and
  the changelog.
- **Don't fear imperfect work.** The hygiene rules below exist so that
  a small PR is genuinely small to review — not to filter you out.

Contributions are licensed under AGPL-3.0. See
[LEGAL.md](LEGAL.md#code-license) for detail.

## Before You Start

1. Read [README.md](README.md) for the architecture model
   (pure SS14 base + curated cherry-picks).
2. Skim [LEGAL.md](LEGAL.md) if you plan to import code from a sibling
   fork — attribution discipline is non-negotiable.
3. Get the dev environment running:
   [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md). Nix + direnv is the
   primary path; `./setup.ubuntu.sh` works for Linux hosts.
4. For non-trivial work, file or claim a bead. See
   [`.claude/skills/beads/SKILL.md`](.claude/skills/beads/SKILL.md). One
   bead = one PR = one logical change.

## Directory Conventions

VS14 uses a directory-prefix scheme so that `git log --follow <path>`
plus the Flavor A boundary SHA is enough to determine the license and
authorship of any line. Pick the right prefix for your change:

| Prefix | Meaning | When to use |
|---|---|---|
| `_VS/` | Original VS14 content | **Default for new content.** AGPL-3.0. |
| _unprefixed_ `Content.*` | Pure SS14 upstream (MIT) | Do not add new files here. Edit existing files only when modifying upstream behavior, and annotate inline (see below). |
| `_DV/` | Delta-V cherry-picks | Only for code imported from Delta-V. Preserve the upstream author. |
| `_NF/` | Frontier cherry-picks | Only for code imported from Frontier. |
| `_EE/`, `_Starlight/`, `_Corvax/`, ... | Other sibling forks | One prefix per upstream, per the attribution table in [README.md](README.md#upstream-attribution). |

New content paths:

```
Content.Server/_VS/...
Content.Shared/_VS/...
Content.Client/_VS/...
Resources/Prototypes/_VS/...
Resources/Locale/en-US/_VS/...
Resources/Textures/_VS/...
Resources/Audio/_VS/...
```

### Modification annotations

When you modify a file that is **not** in an `_<FORK>/` subdirectory,
annotate the changed lines with a subsystem-prefix comment so future
readers (and `git blame`) can tell VS14 edits apart from SS14-upstream
code.

C# (single line):

```csharp
// VS - allow guest connect on community servers
public const bool AllowGuestConnect = true;
```

C# (block):

```csharp
// VS - start
// multi-line edits get explicit bracket comments for easy review
// and conflict resolution against future SS14 upstream pulls
public static readonly TimeSpan DefaultTimeout = TimeSpan.FromSeconds(30);
// VS - end
```

YAML:

```yaml
# VS - bump nutritional value to match _VS recipe rebalance
nutrition: 150
```

Fluent locale files: move the changed string to a corresponding
`_VS/` fluent file and comment out the original in place. Do not
rewrite the upstream string directly.

Partial classes are preferred over inline edits when adding
substantial C# to an upstream type — they keep the upstream file
pristine.

When the modification is itself a cherry-pick from a sibling fork
(e.g. a Delta-V patch that edits an unprefixed SS14 file), use that
fork's tag: `// DV -`, `# NF -`, etc.

### Entity IDs

PascalCase, category prefix. Append `VS` when disambiguation is
needed: `ClothingHeadHatChefVS`, `FoodRecipePastaVS`.

## Commits

See [`.claude/skills/commit/SKILL.md`](.claude/skills/commit/SKILL.md)
for the full convention. In short:

```
<gitmoji> scope: short description

Optional body explaining the why.

Bead: <bead-id>
Co-Authored-By: Someone <noreply@example.com>
```

- One logical change per commit. Squash noise before submitting.
- `Bead: vs-xxx` trailer when the work was bead-tracked.
- `Co-Authored-By:` when AI assistance or pair work was involved
  (transparency, not a gate).
- Gitmoji subjects: `:sparkles:` feature, `:bug:` fix,
  `:memo:` docs, `:recycle:` refactor, `:wrench:` config,
  `:card_file_box:` bead state, `:arrow_up:` upstream sync.

## Changelog

Player-facing changes get a `:cl:` block in the PR description.
See [`.claude/skills/changelog/SKILL.md`](.claude/skills/changelog/SKILL.md)
for full detail.

```
:cl: YourName
- add: Added beachside bar to the oasis station
- tweak: Increased pasta nutrition values
- fix: Fixed soup registering as solid food
```

- Categories: `add`, `remove`, `tweak`, `fix`.
- Active voice, present tense, player-facing wording.
- Admin-only changes go under a `VSADMIN:` header.
  **Never** use `ADMIN:` (collides with SS14 upstream) or
  `DELTAVADMIN:` (wrong project).
- Significant map edits go under a `MAPS:` header with the station
  name as the prefix.
- Internal refactors that players can't see do not need a changelog.

## PR Hygiene

The rules below exist so a small PR stays small to review.

1. **One logical change per PR.** A feature, a fix, a cherry-pick, a
   docs pass — pick one. Multiple independent changes = multiple PRs.
2. **Keep it small.** Aim for under ~500 lines of diff for code PRs.
   Bigger is fine when it's genuinely one change (a new subsystem, a
   large asset import), but pre-warn in the PR body so the reviewer
   knows to plan a longer look.
3. **Rebase before submission.** Clean history, no merge bubbles from
   `main` into your branch. If `main` has moved, rebase.
4. **Minimal file touches.** Don't reformat files you didn't need to
   change. If lint auto-fixes unrelated files, revert those hunks.
5. **Annotate upstream modifications inline** (see the
   [modification annotations](#modification-annotations) section). A
   reviewer should be able to grep for `// VS` or `# VS` and see
   every VS14 edit in an upstream file.
6. **No drafts.** If you open a PR, it's ready for review. Use a
   branch + local iteration for WIP work.
7. **Reference the bead** (if any) in the PR body:
   `Bead: vs-xxx`. Put it in the commit trailer too.
8. **Declare AI assistance** in the PR body if you used it. This is
   for transparency, not gatekeeping.

## Cherry-Pick Discipline

When importing code from a sibling fork, attribution is not optional.
This preserves the license chain and lets `git log --follow` tell the
truth about who wrote what. See
[LEGAL.md](LEGAL.md#per-cherry-pick-attribution-discipline) and
[`docs/upstream-sync.md`](docs/upstream-sync.md) for the legal +
per-upstream context.

For each cherry-pick:

- **Preserve the original author** in the commit's `Author:` line.
  Do not squash into a "VS14 import" commit.
- **Add `Co-Authored-By:`** for the original author if you had to
  resolve conflicts or adapt the patch.
- **Tag the subsystem** in the subject line:
  `:arrow_up: cherry-pick: _NF/Bank from new-frontiers-14@abc1234`
- **Record the upstream commit SHA** in the commit body (the full
  SHA, not a short form).
- **Reference the VS14 bead** that scoped the import.
- **Land the code in the right `_<FORK>/` subsystem.** A cherry-pick
  from Frontier goes under `_NF/`, a Delta-V cherry-pick goes under
  `_DV/`, etc. If no subdirectory exists yet for that upstream, add
  a row to the attribution tables in [README.md](README.md) and
  [LEGAL.md](LEGAL.md) in the same PR that introduces the first
  cherry-pick.
- **Conflict bias**: keep `_VS/` edits verbatim, respect the upstream
  author's intent in `_<OTHER>/`.

PRs that are pure cherry-picks should be labeled as such in the PR
template's "type" field.

## Build & Test Gates

Before requesting review:

```bash
dotnet build                                       # all projects compile
dotnet test Content.Tests --no-build               # unit tests pass
dotnet test Content.IntegrationTests --no-build    # integration tests pass
dotnet run --project Content.YAMLLinter            # prototypes validate
```

For map / prototype / locale changes, the YAML linter is required.
For C# changes, both test suites are required. If a pre-existing
test is broken on `main`, call it out in the PR body rather than
masking it.

## Code of Conduct

Be civil. Disagreements happen; personal attacks, harassment, and
bad-faith engagement do not. Maintainer discretion is final.

---

Questions? File an issue, or open a draft bead if you have
contributor-facing maintainer access.
