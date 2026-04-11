---
description: Git commit conventions with gitmoji, bead trailers, and SS14 changelogs
---

# Commit Convention

## When to Commit

- Every bead closure triggers a commit + push
- One bead = one commit
- Always push after commit (unless in a worktree)

## Message Format

```
<emoji> scope: short description

Optional body.

Bead: <bead-id>
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

Use HEREDOC for multi-line messages:
```bash
git commit -m "$(cat <<'EOF'
:sparkles: cooking: add recipe system

New entity system for combining ingredients.

Bead: vs-xxx
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

## Gitmoji Reference

| Emoji | Use for |
|-------|---------|
| :sparkles: | New feature |
| :bug: | Bug fix |
| :memo: | Documentation |
| :recycle: | Refactoring |
| :white_check_mark: | Tests |
| :wrench: | Configuration |
| :fire: | Remove code/files |
| :zap: | Performance |
| :art: | Style/formatting |
| :ambulance: | Critical hotfix |
| :tada: | Initial commit |
| :card_file_box: | Bead state changes |
| :page_facing_up: | Spec documents |
| :arrow_up: | Upstream sync |

## SS14 Changelog

For player-facing changes, include a changelog block in your PR or commit:

```
:cl: YourName
- add: Added recipe system for combining food items
- fix: Fixed pasta not cooking properly
```

Categories: `add`, `remove`, `tweak`, `fix`

Admin changes: `VSADMIN:` (never `ADMIN:` or `DELTAVADMIN:`)
Map changes: `MAPS:` section

## Safety

- Stage specific files, never `git add -A`
- Never commit `.env`, credentials, or secrets
- Create NEW commits, don't amend unless asked
- Never skip hooks (`--no-verify`)
