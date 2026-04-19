# Guidebook Parity — status per Guide*Embed type

Living doc: what the static guidebook at `https://ss14.zig.computer/guidebook/`
renders for each in-game `Guide*Embed` XML tag, vs what the source YAML
actually carries. Updated as beads close.

Pipeline: `ops/guidebook/render.py` reads
`Resources/Prototypes/**/*.yml` + `Resources/ServerInfo/Guidebook/**/*.xml`
+ `Resources/Locale/en-US/**/*.ftl` and writes one HTML page per
`guideEntry`.

## Legend

- **Full**: every meaningful field in the source YAML reaches the
  static HTML.
- **Partial**: renders a useful subset; fields flagged in "Gaps."
- **Pill**: falls back to the plain-text pill with no data expansion.
- **None**: no loader yet.

## Status table

| Embed tag | Source schema | Status | Rendered today | Gaps / follow-ups |
|---|---|---|---|---|
| `GuideEntityEmbed` | `type: entity` + `Sprite` + stat components | Full | 64px sprite `<img>` + caption + collapsible `<details>` stat block (max health, crit threshold, damage container, `SolutionContainerManager` capacities, `Storage` slots + max item size, `Battery` charge, `Armor` coefficients + flat reductions, `ClothingSpeedModifier` walk/sprint, `MovementSpeedModifier` base speeds). Parent-chain inherits via `_walk_parents` so species children pick up `MobHuman` thresholds. Pure-decorative entities (no stat components) stay sprite-only. Pill fallback remains when RSI missing. | Does not surface `BodyPrototype` organ list or species-specific damage modifiers. `HealthExaminable` damage-type list is not (yet) rendered; consider folding into the stat block once reactions embed lands. |
| `GuideReagentEmbed` (single) | `type: reagent` | Full | Vertical detail card: name + swatch + group pill, description, physical desc, flavor, metabolism rate, bloodstream effects (wiki-voice), plant metabolism (when applicable), threshold ladder, **"Produced by" cross-link section** listing the reactions that yield this reagent (vs-05o.2), Nurseshark footer link | None known — reaction cross-link closes the long-standing gap. |
| `GuideReagentGroupEmbed` | all `type: reagent` w/ matching `group` | Full | 5-column table: Name+swatch, Group, Description, Effects (bulleted, wiki-voice with species notes), Thresholds (max safe dose / Safe / Toxic). Responsive collapse <720px hides Description + Effects columns; the row's thresholds + group remain scannable | Group cells don't link back to the group-embed reactions listing; low value today since the single-reagent card carries its own "Produced by" section. |
| `GuideMicrowaveGroupEmbed` | `type: microwaveMealRecipe` | Full | 5-column table: Result, Recipe name, **Appliance** (hardcoded "Microwave" — column is future-proof for grill / oven / deep fryer), Inputs (sprite + solid × count, reagent Nu), Time in seconds. Responsive collapse <720px hides Appliance | No cross-link from a microwave-recipe's reagent input back to the reaction producing it (e.g. dough → `FlourMixing`); the reverse direction (reagent card → reaction) is now rendered, so the microwave column is only one click away via the reagent chip. |
| `GuideTechDisciplineEmbed` | `type: techDiscipline` + `type: technology` | Partial | 3-column table: Tier, Technology name, Cost | No unlock-chain rendering (prerequisites, dependency tree), no "what this tech grants" (recipe unlocks / new research items). Filed as a Phase 4-sibling follow-up if we want the research UX to parallel the in-game tree. |
| `GuideLawsetListEmbed` | `type: siliconLaw` + `type: siliconLawset` | Full | Per-lawset heading + ordered `<ol>` of laws, resolved through Fluent | None known. |
| `GuideReactionEmbed` (single) | `type: reaction` under `Resources/Prototypes/Recipes/Reactions/**/*.yml` | Full | Vertical reaction card: header (reaction id + source-file-derived group pill), badges (min/max temp in Kelvin, impact Low/Medium/High, mixer-category tool hints like "Requires: Electrolysis", `source: true`, `quantized: true`), Reactants section, distinct Catalysts section ("not consumed"), Products section, Side effects (`SpawnEntity`, `CreateGas`, `Explosion`, `PopupMessage` + anything `_render_effect` handles). Reagent chips carry the reagent's swatch color. Pill fallback when the reaction id isn't indexed. | Reaction `priority:` field (tie-breaker when multiple reactions share reactants) is captured by the loader but not shown today — low signal for the reader. `conserveEnergy:` is captured but not surfaced. |
| `GuideReactionGroupEmbed` | all `type: reaction` under one `Reactions/<stem>.yml` file | Full | 5-column table: Reaction id, Reactants (stacked chips), Catalysts, Products, Temp/Mixer badges. Sorted alphabetically by reaction id. Case-insensitive group lookup (`Group="Medicine"` and `Group="medicine"` both match `medicine.yml`). Responsive collapse <720px hides Catalysts (stays readable in the single-card view). | Groups are derived from filename stem (`medicine`, `botany`, `drinks`, `chemicals`, etc.) — no YAML-authored `group:` field exists on reactions in tree. If SS14 adds one, the renderer switches over transparently via the `group` dict key. |

## Phase history

- **vs-1e5**: initial render.py, text + cross-link + pill fallbacks.
- **vs-mlg**: `GuideEntityEmbed` sprite extraction (Sprite component +
  parent-chain walk + directional PNG slicing).
- **vs-3o7**: Reagent / recipe / tech / lawset table expansion.
- **vs-05o** (this bead, phases 1 + 2 + 3):
  - Reagent tables gain Group + Effects + Thresholds columns.
  - Interpretive English for 40+ known effect types via
    `_render_effect`; unknown types fall back to literal `Type (k=v)`.
  - Single-reagent embeds become vertical detail cards with
    description + physical desc + flavor + metabolism rate +
    bloodstream effects + plant metabolism + threshold ladder +
    Nurseshark cross-link footer.
  - Microwave recipe table gains Appliance column (hardcoded
    "Microwave"); `load_metamorph_recipes` indexes the 5
    `metamorphRecipe` prototypes for future embed use (no in-game
    embed surfaces them today).
  - Responsive collapse <720px hides verbose columns (CSS media query).
  - Unit tests in `ops/guidebook/test_render.py` — 8 green.
  - Module docstring cites the SS14 wiki pages that anchor our
    interpretive voice.
- **vs-05o.1** (Phase 4 — entity stat blocks):
  - `load_entity_sprites` now also captures `MobThresholds`,
    `Damageable`, `SolutionContainerManager`, `Storage`, `Battery`,
    `PowerCell`, `Armor`, `ClothingSpeedModifier`, and
    `MovementSpeedModifier` into each entity's `stat_components` map.
  - `_resolve_entity_components` walks the parent chain the same way
    `resolve_sprite` does — child declarations beat ancestors, so
    e.g. syndicate-agent variants inherit MobHuman's health thresholds.
  - `_render_entity_stats_block` emits a collapsible `<details>` below
    the sprite with a two-column `label → value` table: max health,
    crit threshold, damage container, per-solution reagent caps,
    storage slots + max item size, max/starting charge, per-damage-type
    armor (`0.8` → `20% reduction`, `0` → `immune`, `1.2` → `+20%
    vulnerability`), walk/sprint modifiers, and base movement speeds.
  - Pure-decorative entities (no matching components anywhere in the
    chain) render the same inline sprite layout as before.
  - 9 new pytest cases cover MaxHealth inheritance from `MobHuman`,
    reagent capacity, storage grid area, PowerCell charge, armor
    coefficient formatting, clothing slowdown, the
    no-stat-components degrade-to-sprite case, the `<details>` +
    `<table>` wrapper shape, and the decorative-entity filter that
    suppresses lone `damage container` rows for posters and static
    structures. Total: 22 green.
- **vs-05o.2** (Phase 5 — reaction embeds + reagent cross-links):
  - `load_reactions(repo)` indexes `type: reaction` under
    `Resources/Prototypes/Recipes/Reactions/**/*.yml` — 313 reactions
    in tree today (37 temperature-gated, 12 catalyzed, 75 mixer-required,
    39 with side-effects, 70 impact-tagged). Groups are derived from
    filename stem since no YAML `group:` field exists on reactions.
  - Reverse index `_REAGENT_TO_REACTIONS` maps reagent id → list of
    reactions that produce it (265 reagents covered). Catalysts are
    intentionally excluded — only `products:` entries count as
    "produces."
  - `GuideReactionEmbed` renders a vertical card with header (id + group
    pill), badge row (temp in Kelvin, impact, mixer categories, source,
    quantized), then Reactants / Catalysts / Products / Side effects
    sections. Catalyst rows are distinct from reactants and carry a
    "not consumed" annotation.
  - `GuideReactionGroupEmbed Group="medicine"` renders a 5-column table
    sorted by reaction id, with stacked reagent chips per column.
    Group lookup is case-insensitive so authors can write `"Medicine"`.
  - Side effects reuse Phase 1's `_render_effect` pipeline; plus new
    reaction-specific interpretations for `SpawnEntity`, `CreateGas`,
    `Explosion`, `EmpPulse`, `AreaReactionEffect`.
  - Single-reagent detail cards (`GuideReagentEmbed`) gain a "Produced
    by" section listing each producing reaction as a compact one-liner
    (`Inaprovaline 1u + Carbon 1u → Bicaridine 2u`) with temp/mixer
    badges inline. Orphan reagents (e.g. Water, base elements) simply
    skip the section rather than rendering an empty stub.
  - 11 new pytest cases cover: single reaction card shape, catalyst
    distinction (Leporazine + Plasma), temperature gate badge
    (Pyrazine minTemp 540), mixer tool hint (SpaceGlue + Stir), group
    rendering with multiple reactions, case-insensitive group lookup,
    "Produced by" cross-link, absence on orphans, side-effect reuse
    (ChlorineTrifluoride Explosion), unknown-reaction pill fallback,
    and reverse-index construction. Total: 33 green.
  - New CSS: `.reaction-card`, `.reaction-badge-*` (temp / mixer /
    impact tiers / source / quantized), `.reaction-reagent-chip` with
    swatch, `.reagent-produced-by .produced-by-list`, responsive
    collapse hides the Catalysts column <720px.
- **vs-dnz** (JS-enhanced nav — matches in-game UX where sidebar
  stays stable while content swaps):
  - Sidebar parent entries render as `<details data-section-id="...">`
    so collapse state survives across pages.
  - Inline `<head>` bootstrap script reads
    `localStorage["vs14-guidebook-nav-state"]`
    (`{ "section-id": "open", ... }`) pre-paint, plus force-opens the
    active entry's ancestor chain so the current page is always visible.
  - `guidebook-nav.js` (shipped alongside HTML) intercepts
    `<a data-nav-link>` clicks: fetches the target page, extracts
    `#content`, swaps innerHTML, `history.pushState`s, updates
    `<title>` + `aria-current`, scrolls content to top, fires a
    `nav:loaded` event. `popstate` runs the same swap pipeline.
    Fetch / parse failures fall back to `location.href = href` (full
    reload), and the raw `href` attribute is always the real URL, so
    no-JS browsers keep the original full-page nav behavior.
  - `<main id="content">` now wraps the per-page body as the stable
    swap target.
  - "Expand all" / "Collapse all" buttons at the top of the sidebar.
  - Chevron indicator (▸ closed, rotates 90° when open), 150ms CSS
    transitions (respects `prefers-reduced-motion`).
  - 5 new unit tests in `ops/guidebook/test_render.py` (total: 13
    green). JS behavior is manual-verify only (no jsdom in the
    guidebook's Python stack).

## Scope deferred to follow-up beads

- **Phase 5 landed** (vs-05o.2): all in-game `Guide*Embed` tags now
  render at Full parity. Remaining guidebook work is editorial /
  curation rather than loader gaps.
- **Other loaders currently idle**:
  - `metamorphRecipe` (5 indexed, no embed).
  - `foodSequenceElement` (burger layers — no embed today).
  - `SliceableFoodComponent` (cutting recipes — requires entity
    component scan, not a loader).
- **XML authoring cross-link hygiene**: no in-tree guidebook XML uses
  `<GuideReactionEmbed/>` or `<GuideReactionGroupEmbed/>` yet. Phase 5
  ships the rendering; wiring the chemistry / medicine pages to embed
  the reaction table is a content-authoring follow-up (small YAML/XML
  PR against `Resources/ServerInfo/Guidebook/Chemistry.xml` et al).

## Gap call-outs for future work

- **Species-specific nuance**: Effects carrying a
  `MetabolizerTypeCondition` already surface their species in
  parentheses ("only for Vox"). Arachnid iron-toxicity, moth insect
  blood, Diona sap — these are content-authored in separate reagents
  and render correctly, but the wiki's connective prose
  ("use Copper instead for arachnids") is only implicit. A curated
  "species caveats" section per-species would require hand-authored
  markdown, not render.py.
- **Wiki-voice warnings** (e.g. Razorium mix warning, Tricordrazine
  "below 50 damage," Epinephrine "critical-state only heals"): these
  require editorial hand-authoring. Recommend a `_VS/` wiki-extras
  Fluent namespace or per-reagent override YAML to augment the
  auto-rendered card; out of scope for the pure-mechanical parity
  sweep.
