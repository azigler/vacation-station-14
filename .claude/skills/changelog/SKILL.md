---
description: Generate SS14-format changelogs for player-facing changes
---

# Changelog

Player-facing changelogs follow SS14's `:cl:` format.

## Format

```
:cl: YourName
- add: Added a new feature
- remove: Removed an old feature
- tweak: Tuned an existing feature
- fix: Fixed a bug
```

## Categories

| Category | Use For |
|----------|---------|
| `add` | New features, items, recipes |
| `remove` | Removed features, items |
| `tweak` | Balance changes, UX tweaks |
| `fix` | Bug fixes |

## Writing Entries

- Complete, grammatical sentences
- Active voice, present tense
- Player-facing language (not technical jargon)
- Start with a verb
- No changelogs for internal refactors players can't see

## Admin Changelog

For admin-only changes (ban system, admin tools):

```
:cl: YourName
VSADMIN:
- add: Added new admin panel for plot management
- fix: Fixed ban appeals not sending DMs
```

**Never use `ADMIN:` (mangles upstream) or `DELTAVADMIN:` (wrong project).**

## Map Changelog

For significant map changes:

```
:cl: YourName
MAPS:
- add: Oasis: Added beach bar to south section
- tweak: Oasis: Widened main corridor
- fix: Oasis: Fixed unpowered APC in engineering
```

Minor map edits don't need changelogs.

## Multiple Categories

```
:cl: YourName
- add: Added pasta recipes
- add: Added chef hat cosmetic
- tweak: Increased food nutrition values
- fix: Fixed soup showing as solid food
VSADMIN:
- add: Added recipe inspection admin verb
```

## In PR Descriptions

Put the `:cl:` block at the end of your PR description. The changelog bot
parses it automatically.
