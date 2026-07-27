# Agent configuration lives in the operator repo, not here

This repository is **the game**. It deliberately carries no `CLAUDE.md`, no
`.claude/`, and no hook scripts.

The agentic operator for this server is **`vs14d`**
(`https://github.com/azigler/vs14d`). It carries this repository as a submodule
and holds all of it: project instructions, skills, hooks, and the Green-keeper
loop that keeps this fork current with upstream.

Separation of concerns, decided 2026-07-27: **agentics belong in the operator
repo.** A game repo that also configures the agent is two things wearing one
name — and the harness that used to sit here had already drifted hundreds of
lines from the fleet's global one, so it was actively misleading as well as
misplaced.

## Where the moved pieces went

| Was | Now |
|---|---|
| `CLAUDE.md` | `vs14d/refs/vs14-game-repo.md` — verbatim. It was real game-domain knowledge (subsystem prefixes, the AGPL boundary commit, code conventions); only its filename made it look like agent instructions. |
| `.claude/skills/` (9 skills) | `vs14d/.claude/skills/` — build, changelog, nix, prototype, services, upstream-sync, vibe-maintainer, vs14-brand, vs14-voice |
| `.claude/settings.json` + `hooks/` (9 scripts) | **not carried across.** They duplicated hooks that now run globally for every project; installing them alongside would double-fire every check. They remain in this repo's git history. |

`docs/` is unchanged and remains the place for public technical documentation
about the game itself.
