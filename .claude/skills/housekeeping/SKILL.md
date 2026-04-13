---
description: Mechanical text work — stale doc refreshes, bead-state cleanups, reference sync, deprecation markers, directory renames. No design decisions.
---

# Housekeeping

Mechanical, non-creative changes that don't introduce new logic or behavior.
Run this after a chunk of work lands and the docs / beads / README drift
from reality.

## What Housekeeping IS

- Deleting deprecated code (entire directories, files, dead imports)
- Syncing `docs/upstream-sync.md`, README attribution table, `CLAUDE.md`,
  and `LEGAL.md` when remotes / submodules / directory prefixes change
- Updating bead descriptions + notes when scope shifts (not creating new
  beads — that's `/spec`)
- Closing bookkeeping beads (`:card_file_box:`) when the underlying work
  is done but paperwork isn't
- Terminology renames (find-and-replace across files)
- Version bumps (`global.json`, `.csproj`, flake inputs)
- Stale doc/table cleanup (removing hardcoded counts, outdated port tables)
- `.gitignore` updates
- Skill file creation or maintenance
- Fixing broken internal links or cross-references
- Removing stale bead deps (`br dep remove <a> <b>`) when architecture
  changes
- Git hygiene: delete abandoned branches, prune stale tags that aren't
  anchoring something

All of these are deterministic text transformations + bead state
updates. No design judgment required.

## What Housekeeping is NOT

- New features or capabilities (use `/spec` → `/test` → `/impl`)
- Cherry-picks from upstream forks (use `/upstream-sync`)
- New bead creation with non-trivial scope (use `/spec`)
- Test writing for new features (use `/test`)
- Open question resolution (use `/review`)
- Refactoring that changes behavior or API surface (use `/impl`)

If you're uncertain, ask: "Does this require reading a bead description
or making a design decision?" If yes, it's not housekeeping.

## Workflow

### 1. Inventory — what drifted

Pull the current state of reality vs. the current state of docs:

```bash
# What's actually in the repo now
git remote -v
git submodule status
ls external/ services/ 2>/dev/null
br list --status open 2>&1 | grep "^○" | wc -l

# What the docs claim
grep -E "upstream-|external/|services/" docs/upstream-sync.md
grep -E "_VS|_DV|_NF|_RMC|_HL" README.md
grep -iE "phase|status" README.md CLAUDE.md
```

Group the deltas by type:

| Type | What to check |
|------|---------------|
| **Remotes** | `git remote -v` vs. the table in `docs/upstream-sync.md` |
| **Submodules** | `git submodule status` vs. docs/upstream-sync's submodule table |
| **Subsystem prefixes** | `ls Content.Server/_*/ Content.Client/_*/ Resources/Prototypes/_*/` vs. README's attribution table |
| **Endpoints** | `ops/nginx/*.conf` location blocks vs. `docs/NETWORKING.md` |
| **Services** | `systemctl list-units "vs14-*"` + `docker ps` vs. `docs/OPERATIONS.md` "Service inventory" |
| **Beads** | `br list --status open` — any that should have closed already? stale `in_progress` claims? |
| **Tags** | `git tag -l` — anything orphaned? |
| **Branches** | `git branch -a` — local or remote branches abandoned? |

### 2. Verify before deleting

Before deleting anything (directory, file, branch, tag, bead dep):

```bash
# Find references
git grep "target-name"
grep -r "target-name" docs/ ops/ .claude/

# For directories
rg "using Content\.Server\._Target" --type cs
rg "Resources/Prototypes/_Target"
```

If a reference exists outside the deletion target, classify:
- **Also being cleaned up in this pass** — safe, proceed
- **Not being cleaned up** — STOP. Open-code impact = `/impl` work, not
  housekeeping.

### 3. Apply changes

Work in this order to avoid broken intermediate states:

1. **Delete code / files / submodules** — whatever's going away
2. **Delete stale tests** for removed code
3. **Delete abandoned branches + tags** on origin
4. **Update remotes / submodules** in `.gitmodules` (in-tree), push
5. **Rewrite bead descriptions / notes** for scope drift (`br update`)
6. **Close done-but-unfiled beads** (`br close`)
7. **Remove dead bead deps** (`br dep remove`)
8. **Sync docs** (see checklist below)
9. **Commit + push** in atomic pieces

### 4. Verify (deterministic gates)

```bash
# Confirm deletions — grep should return nothing for removed paths
git grep "target-name"

# Confirm no dangling imports in C#
dotnet build --configuration DebugOpt 2>&1 | grep error

# Confirm beads coherent
br blocked
br ready | wc -l
br epic status

# Confirm workflows still parse (catches YAML breakage after renames)
for f in .github/workflows/*.yml; do
    python3 -c "import yaml; yaml.safe_load(open('$f'))" || echo "BAD: $f"
done

# Confirm live endpoints still work if we touched nginx/ops
for p in / /recipes/ /maps/ /writer/ /client.zip; do
    curl -sS -o /dev/null -w "$p %{http_code}\n" "https://ss14.zig.computer$p"
done
```

**Never trust a self-reported "done" without grep or a live smoke test.**

### 5. Commit discipline

Each commit independently valid. Suggested split for a full pass:

| Emoji | Scope |
|---|---|
| `:fire:` | Deletions (code, files, obsolete scaffolding) |
| `:truck:` | Renames, moves (e.g. `external/<x>/` → `services/<x>/` migration) |
| `:wrench:` | Config / tooling (.gitignore, shell.nix, global.json bumps) |
| `:memo:` | Doc updates (README, CLAUDE, LEGAL, docs/, skills) |
| `:card_file_box:` | Bead state + dep changes |
| `:art:` | Formatting-only (rare; prefer combining with `:memo:`) |

Include `Bead: <id>` trailer when the housekeeping stems from a
specific closed or in-progress bead.

## Doc + bead sync checklist

Every housekeeping pass ends with this audit:

### `CLAUDE.md`
- Architecture section — subsystem prefixes (`_VS/`, `_DV/`, etc.) match reality
- Remotes list matches `git remote -v`
- License section commit SHA still points at the current boundary
- Build & Test section — commands still run
- Commit convention and changelog format current

### `README.md`
- Upstream attribution table — every active remote + submodule has a row
- License boundary statement cites the right commit SHA + tag
- Endpoint / service list (if present) matches nginx vhost
- Connect URL (`ss14://...`) matches the deployed hostname
- Link list at bottom — no dead links

### `LEGAL.md`
- License verification record has a row for every active upstream
- Per-service compliance section covers every deployed bundled service
- Wizden OAuth + DMCA placeholders — updated if we've made progress on
  `vs-1ux` or `vs-3tq`

### `docs/upstream-sync.md`
- Remotes table matches `git remote -v`
- Submodules table matches `.gitmodules`
- License boundary commit SHA + tag current
- Planned upstreams section reflects actual curation intent

### `docs/NETWORKING.md` / `docs/OPERATIONS.md` / `docs/DEVELOPMENT.md`
- Port tables + vhost paths match `ops/nginx/*.conf`
- Bundled service inventory matches `ops/<name>/` + `external/<name>/`
- Any env vars / secrets references point at current locations

### `.claude/skills/*/SKILL.md`
- Obsolete skills removed (or their description updated to reflect the
  new pattern)
- Cross-links between skills work — no pointing at skills we've renamed
- `/services`, `/nix`, `/upstream-sync`, `/vibe-maintainer` tend to
  drift when infra changes

### Beads
- Every `in_progress` bead has recent activity (or drop back to `open`)
- Closed epics where all children are closed (or close them explicitly
  with `br epic close-eligible`)
- No dangling `blocks` deps pointing at closed beads (they auto-resolve
  but look noisy in `br dep tree`)
- Bead notes don't reference paths / files / tags that have been
  renamed or removed

### Memory (`~/.claude/projects/.../memory/`)
- Stale project memories (old phases, deprecated names) — prune or update
- Missing memories — anything from this session worth persisting?
- `MEMORY.md` index matches the actual memory files

## Scope limits for one pass

A good housekeeping commit set is 5-10 small commits. If the pass
balloons past that, something is probably not housekeeping — spin out
a proper scoped bead for the substantial piece.

Shibboleths for "this is actually impl work":
- You're editing `.cs` files with `dotnet build` feedback loops
- You're reading beads to understand their acceptance criteria
- You're making choices where there's more than one defensible option
- You're running tests

When any of those fire, stop housekeeping and open a bead for the work.
