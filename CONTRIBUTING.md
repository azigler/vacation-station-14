# Vacation Station 14 Contributing Guidelines

We follow [upstream SS14 conventions](https://docs.spacestation14.com/en/general-development/codebase-info/conventions.html)
and [PR guidelines](https://docs.spacestation14.com/en/general-development/codebase-info/pull-request-guidelines.html)
for code quality.

Do not use GitHub's web editor to create PRs.

## AI-Assisted Development

This project is built and maintained with AI assistance. We are transparent
about this because we believe in honest open-source development.

We welcome contributions regardless of tooling. Our standard is quality:
code must be correct, tested, well-structured, and maintainable.

If you used AI tools in your development process:
- Understand every line you're submitting
- Test thoroughly in-game
- Be prepared to explain your implementation

## Content Specific to Vacation Station

Anything you create from scratch should go in a `_VS` subfolder.

Examples:
- `Content.Server/_VS/Cooking/RecipeSystem.cs`
- `Resources/Prototypes/_VS/Recipes/food.yml`
- `Resources/Audio/_VS/Effects/sizzle.ogg`
- `Resources/Textures/_VS/Objects/Food/pasta.rsi`
- `Resources/Locale/en-US/_VS/cooking/recipes.ftl`
- `Resources/ServerInfo/Guidebook/_VS/Cooking.xml`
  Note that guidebooks go in `ServerInfo/Guidebook/_VS` and not `ServerInfo/_VS`!

## Changes to Upstream Files

When modifying files outside `_VS`, `_DV`, or `Nyanotrasen` folders, **add comments
on or around all new or changed lines** to help manage upstream merges.

### YAML (.yml) Files

Add comments on or around changed lines:

```yml
- type: entity
  parent: FoodBase
  id: FoodPastaVS
  components:
  - type: FlavorProfile # VS - Custom flavor system
    flavors:
    - Savory
    - Umami
```

For blocks of additions:
```yml
# Begin VS additions
- id: FoodPastaVS
- id: FoodSoupVS
# End VS additions
```

For removed lines:
```yml
#- id: SomeOldThing # VS - removed, replaced by new system
```

### C# (.cs) Files

Use partial classes when adding substantial code to upstream types.

Otherwise, add comments on changed lines:

```cs
using Content.Server._VS.Cooking; // VS
```

```cs
// VS - start of recipe validation
var recipe = GetRecipe(uid);
if (recipe == null) return;
// VS - end of recipe validation
```

### Fluent (.ftl) Localization Files

**Move changed strings to a `_VS` file.** Comment out the old strings in the
upstream file:

```
# VS - moved to _VS file
#old-string = Old value
```

Create the new version in `Resources/Locale/en-US/_VS/<same-path>/<same-file>.ftl`.

Fluent files do not support inline comments on value lines.

## Mapping

Contact the map maintainer before making changes. Map conflicts make PRs
mutually exclusive.

List all changes with locations when submitting a map PR.

## Before You Submit

- Double-check your diff for unintended changes
- If `RobustToolbox` appears in changed files, revert it:
  `git checkout upstream/master RobustToolbox`
- Test in-game for gameplay changes (screenshots/video appreciated)

## Changelogs

Default changelogs go in the Vacation Station changelog:

```
:cl: YourName
- add: Added a thing!
- remove: Removed a thing!
- tweak: Changed a thing!
- fix: Fixed a thing!
```

Admin changelog: use `VSADMIN:` (never `ADMIN:` or `DELTAVADMIN:`).

Map changelog format:
```
:cl: YourName
MAPS:
- add: MapName: Added a thing!
- tweak: MapName: Changed a thing!
```

## License

All contributions must be licensed under AGPL-3.0. See `LEGAL.md` for details.

## Getting Help

If you're new to SS14 development, check the
[SS14 docs](https://docs.spacestation14.com/) or ask in our Discord.
