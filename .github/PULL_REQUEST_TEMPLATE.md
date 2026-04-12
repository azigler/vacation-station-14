<!--
Thanks for contributing. See CONTRIBUTING.md for the hygiene rules.
Short version: one logical change, rebased on main, annotate upstream
edits with `// VS` / `// DV` / etc. comments. AI-assisted PRs are
welcome — flag them below for transparency.
-->

## Summary

<!-- 1-2 sentences. What does this change and why? -->

## Bead

<!-- Paste the bead ID if bead-tracked; otherwise "none". -->
Bead: vs-xxx

## Type

<!-- Check one. -->
- [ ] Feature (new `_VS/` content or capability)
- [ ] Bugfix
- [ ] Cherry-pick from sibling fork
- [ ] Docs / CI / ops
- [ ] Refactor (no behavior change)

## Cherry-pick details

<!-- Only if this is a cherry-pick. Otherwise delete this section.
See CONTRIBUTING.md#cherry-pick-discipline and LEGAL.md for the
attribution rules. -->
- Upstream: <!-- e.g. new-frontiers-14/frontier-station-14 -->
- Upstream commit SHA: <!-- full SHA, not short -->
- Landed under: <!-- e.g. Content.Server/_NF/Bank -->
- Original author preserved in commit `Author:` line: [ ]

## Testing done

<!-- What did you run? Paste relevant output if useful.
At minimum, for code changes:
  - dotnet build
  - dotnet test Content.Tests --no-build
  - dotnet test Content.IntegrationTests --no-build
  - dotnet run --project Content.YAMLLinter   (for prototype/YAML changes)
-->

## Hygiene checklist

- [ ] One logical change (see `CONTRIBUTING.md` - PR Hygiene)
- [ ] Rebased on `main`, no merge bubbles
- [ ] Upstream-file edits annotated inline (`// VS`, `# VS`, etc.)
- [ ] New content lives under an `_<FORK>/` subdirectory
- [ ] Build + tests pass locally

## AI assistance

<!-- Transparency only, not a gate. -->
- [ ] This PR was AI-assisted (any non-trivial generation, drafting,
      or refactor). If yes, add a `Co-Authored-By:` trailer to your
      commit and mention the tool in the summary.

## Changelog

<!-- Include a `:cl:` block ONLY for player-facing changes.
See .claude/skills/changelog/SKILL.md for the full format.
Delete this section entirely for internal-only changes.

:cl: YourName
- add: Added a thing
- tweak: Tuned a thing
- fix: Fixed a thing
-->
