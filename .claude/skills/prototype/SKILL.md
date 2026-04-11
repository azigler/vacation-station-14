---
description: Create YAML entity prototypes following SS14 conventions
---

# Prototype Creation

Create YAML entity prototypes in `Resources/Prototypes/_VS/`.

## Naming

Entity IDs use PascalCase with category prefix, append `VS` suffix when disambiguating:
- `FoodPastaCarbonaraVS`
- `ClothingHeadHatChefVS`
- `ItemRollingPinVS`

## Field Order

```yaml
- type: entity
  abstract: true              # if applicable
  parent: FoodBase            # single or list
  id: FoodPastaCarbonaraVS
  categories:                 # if applicable
  - HideSpawnMenu
  name: carbonara
  suffix: VS                  # if applicable for disambiguation
  description: Rich, creamy, and full of regret.
  components:
  - type: Sprite              # engine components near top
    sprite: _VS/Objects/Food/pasta.rsi
    state: carbonara
  - type: Item
    size: Small
  - type: Food                # content components
  - type: FlavorProfile
    flavors:
    - Savory
    - Creamy
```

## Common Patterns

### Food Item
```yaml
- type: entity
  parent: FoodBase
  id: FoodPastaCarbonaraVS
  name: carbonara
  description: ...
  components:
  - type: Sprite
    sprite: _VS/Objects/Food/pasta.rsi
    state: carbonara
  - type: SolutionContainerManager
    solutions:
      food:
        maxVol: 20
        reagents:
        - ReagentId: Nutriment
          Quantity: 15
  - type: FlavorProfile
    flavors:
    - Savory
```

### Clothing
```yaml
- type: entity
  parent: ClothingHeadBase
  id: ClothingHeadHatChefVS
  name: chef hat
  description: ...
  components:
  - type: Sprite
    sprite: _VS/Clothing/Head/Hats/chefhat.rsi
  - type: Clothing
    sprite: _VS/Clothing/Head/Hats/chefhat.rsi
```

### Recipe
```yaml
- type: microwaveMealRecipe
  id: RecipeCarbonaraVS
  name: carbonara
  result: FoodPastaCarbonaraVS
  time: 10
  solids:
    FoodDoughSlice: 1
    FoodEgg: 1
  reagents:
    Cream: 10
```

## File Organization

Group prototypes by category in `Resources/Prototypes/_VS/`:
- `Catalog/Fills/` -- loot tables
- `Entities/Clothing/` -- clothing
- `Entities/Objects/Consumable/` -- food, drinks
- `Entities/Structures/` -- machines, furniture
- `Recipes/` -- crafting, cooking, chemistry
- `GameRules/` -- event rules

## Sprites

Sprite files (RSI) go in `Resources/Textures/_VS/`:
- `_VS/Objects/Food/pasta.rsi/` (directory with meta.json + PNGs)

## Localization

Player-visible strings go in `Resources/Locale/en-US/_VS/`:

```
# Resources/Locale/en-US/_VS/food/pasta.ftl
ent-FoodPastaCarbonaraVS = carbonara
    .desc = Rich, creamy, and full of regret.
```

Use kebab-case for loc IDs. Never show `Enum.ToString()` to players.

## Validation

```bash
dotnet run --project Content.YAMLLinter
```

Fix all errors before committing.
