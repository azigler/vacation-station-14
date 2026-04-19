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
| `GuideEntityEmbed` | `type: entity` + `Sprite` component | Partial | 64px sprite `<img>` + caption; pill fallback when RSI missing (91.2% hit rate at last build) | No stat block — `MaxHealth`, armor, container capacity, species info, power-cell capacity. **Phase 4 follow-up bead.** |
| `GuideReagentEmbed` (single) | `type: reagent` | Full | Vertical detail card: name + swatch + group pill, description, physical desc, flavor, metabolism rate, bloodstream effects (wiki-voice), plant metabolism (when applicable), threshold ladder, Nurseshark footer link | Cross-link to reactions that **produce** this reagent is not yet rendered — needs Phase 5 reactions embed first. |
| `GuideReagentGroupEmbed` | all `type: reagent` w/ matching `group` | Full | 5-column table: Name+swatch, Group, Description, Effects (bulleted, wiki-voice with species notes), Thresholds (max safe dose / Safe / Toxic). Responsive collapse <720px hides Description + Effects columns; the row's thresholds + group remain scannable | Same reactions cross-link gap as single embed. |
| `GuideMicrowaveGroupEmbed` | `type: microwaveMealRecipe` | Full | 5-column table: Result, Recipe name, **Appliance** (hardcoded "Microwave" — column is future-proof for grill / oven / deep fryer), Inputs (sprite + solid × count, reagent Nu), Time in seconds. Responsive collapse <720px hides Appliance | No integration with reactions — e.g. dough is a chemistry reaction prerequisite for many recipes; that cross-link is deferred (part of Phase 5 reactions embed). |
| `GuideTechDisciplineEmbed` | `type: techDiscipline` + `type: technology` | Partial | 3-column table: Tier, Technology name, Cost | No unlock-chain rendering (prerequisites, dependency tree), no "what this tech grants" (recipe unlocks / new research items). Filed as a Phase 4-sibling follow-up if we want the research UX to parallel the in-game tree. |
| `GuideLawsetListEmbed` | `type: siliconLaw` + `type: siliconLawset` | Full | Per-lawset heading + ordered `<ol>` of laws, resolved through Fluent | None known. |
| _`GuideReactionEmbed` (not yet implemented)_ | `type: reaction` under `Resources/Prototypes/Recipes/Reactions/**/*.yml` | None | — | Brand-new embed type proposed in Phase 5 — reactants + catalysts + products + minTemp + impact. |

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

- **Phase 4** — entity stat blocks on `GuideEntityEmbed`. Scope:
  collapsible `<details>` under each sprite showing `MaxHealth` (from
  `MobState` or direct `DamageContainer.healthCap`),
  `SolutionContainerManager` capacity, `Storage` capacity, and any
  `BodyPrototype`/species fields. Complication: stat inheritance walks
  the same parent chain as sprites (`_walk_parents` already exists and
  can be reused). No new embed type, just a renderer extension.
- **Phase 5** — `GuideReactionEmbed` + `GuideReactionGroupEmbed`.
  Scope: new loader for `type: reaction`, new XML tag support, and a
  cross-link from each reagent's detail card listing the reactions
  that produce it. Fold into Phase 1 effect rendering for
  reactant/product reagent name resolution. Initial scan:
  `~300 reactions` under `Resources/Prototypes/Recipes/Reactions/**`.
- **Other loaders currently idle**:
  - `metamorphRecipe` (5 indexed, no embed).
  - `foodSequenceElement` (burger layers — no embed today).
  - `SliceableFoodComponent` (cutting recipes — requires entity
    component scan, not a loader).

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
