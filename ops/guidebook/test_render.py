"""Unit tests for ops/guidebook/render.py (vs-05o).

Run from the worktree root:

    python3 -m pytest ops/guidebook/test_render.py -v

Or without pytest:

    python3 ops/guidebook/test_render.py

The tests exercise the reagent-effect rendering pipeline end-to-end
using tiny inline YAML fixtures (no repo I/O), plus the microwave-
recipe Appliance column rendering. They cover:

  1. Bicaridine's effect chain (healing + OD ladder)
  2. A reagent with no effects (empty Effects cell, "Safe" threshold)
  3. A reagent with plantMetabolism (leaf-prefixed plant section)
  4. Microwave recipe row shows an Appliance="Microwave" column
  5. Unknown effect type falls back to literal "Type (k=v)" dump

The render.py module stores prototype data in module-global dicts
populated by `render_site`; the tests populate those directly for
unit isolation.
"""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import yaml

# Allow `python3 test_render.py` from the ops/guidebook dir or repo root.
THIS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(THIS_DIR))

import render  # noqa: E402


def _load_reagent(text: str) -> dict:
    """Parse a single `- type: reagent` block into a loader-tagged dict."""
    docs = yaml.load(text, Loader=render._TagRecordingLoader)
    assert isinstance(docs, list) and docs, "fixture must be a YAML list"
    return docs[0]


def _install_reagent(raw: dict) -> str:
    """Register a reagent dict into render._REAGENTS and return its id."""
    rid = raw["id"]
    effects, rate = render._extract_bloodstream_effects(raw)
    render._REAGENTS[rid] = {
        "id": rid,
        "name_key": raw.get("name") or f"reagent-name-{rid.lower()}",
        "desc_key": raw.get("desc") or f"reagent-desc-{rid.lower()}",
        "physical_desc_key": raw.get("physicalDesc"),
        "flavor": raw.get("flavor"),
        "group": raw.get("group") or "Unknown",
        "color": raw.get("color"),
        "bloodstream_effects": effects,
        "plant_effects": render._extract_plant_effects(raw),
        "metabolism_rate": rate,
    }
    return rid


def _reset_state() -> None:
    render._REAGENTS.clear()
    render._MICROWAVE_RECIPES.clear()
    render._LOCALE.clear()
    # Populate the damage-type labels the renderer consults.
    render._LOCALE.update(
        {
            "damage-type-poison": "Poison",
            "damage-type-asphyxiation": "Asphyxiation",
            "damage-group-brute": "Brute",
            "damage-type-blunt": "Blunt",
            "damage-type-radiation": "Radiation",
            "damage-type-caustic": "Caustic",
            "reagent-name-bicaridine": "Bicaridine",
            "reagent-desc-bicaridine": "Heals brute damage.",
            "reagent-name-water": "Water",
            "reagent-desc-water": "A ubiquitous solvent.",
            "reagent-name-pestkiller": "Pest Killer",
            "reagent-desc-pestkiller": "Deters plant pests.",
            "reagent-name-mystery": "Mystery",
            "reagent-desc-mystery": "Unknown substance.",
        }
    )


# ---------------------------------------------------------------------------
# Phase 1 — reagent effects
# ---------------------------------------------------------------------------


BICARIDINE_YAML = """
- type: reagent
  id: Bicaridine
  name: reagent-name-bicaridine
  desc: reagent-desc-bicaridine
  group: Medicine
  color: "#ffaa00"
  metabolisms:
    Bloodstream:
      metabolismRate: 0.5
      effects:
      - !type:EvenHealthChange
        damage:
          Brute: -1.5
      - !type:HealthChange
        conditions:
        - !type:ReagentCondition
          reagent: Bicaridine
          min: 15
        damage:
          types:
            Asphyxiation: 0.5
            Poison: 1.5
      - !type:Vomit
        conditions:
        - !type:ReagentCondition
          reagent: Bicaridine
          min: 30
        probability: 0.02
      - !type:Jitter
        conditions:
        - !type:ReagentCondition
          reagent: Bicaridine
          min: 15
      - !type:Drunk
"""


def test_bicaridine_heal_and_overdose_ladder() -> None:
    _reset_state()
    raw = _load_reagent(BICARIDINE_YAML)
    _install_reagent(raw)

    row = render._reagent_row("Bicaridine")
    assert row is not None
    assert "Bicaridine" in row
    # Healing
    assert "heals 1.5 Brute per unit" in row
    # Group pill
    assert "Medicine" in row
    # Threshold cell
    assert "max safe dose 15u" in row
    # Effects list rendered
    assert "deals 0.5 Asphyxiation" in row
    # Vomit threshold note
    assert "induces vomiting" in row

    # Detail view (GuideReagentEmbed): contains ladder, metabolism rate,
    # Nurseshark footer, and interpretive healing copy.
    elem = ET.Element("GuideReagentEmbed", {"Reagent": "Bicaridine"})
    card = render._render_reagent_embed(elem)
    assert "reagent-card" in card
    assert "above 15u" in card
    assert "above 30u" in card
    assert "Metabolism rate" in card
    assert "0.5 u/s" in card
    assert "nurseshark/reagents/Bicaridine" in card


def test_max_safe_dose_conservative() -> None:
    _reset_state()
    raw = _load_reagent(BICARIDINE_YAML)
    _install_reagent(raw)
    effects = render._REAGENTS["Bicaridine"]["bloodstream_effects"]
    # Smallest harmful threshold is 15 (the HealthChange damage at 15u).
    assert render._max_safe_dose(effects) == 15.0


# ---------------------------------------------------------------------------
# Clean no-effect reagent (Safe cell, empty Effects)
# ---------------------------------------------------------------------------


WATER_YAML = """
- type: reagent
  id: Water
  name: reagent-name-water
  desc: reagent-desc-water
  group: Drink
  color: "#6699ff"
"""


def test_no_effects_row_renders_clean() -> None:
    _reset_state()
    raw = _load_reagent(WATER_YAML)
    _install_reagent(raw)

    row = render._reagent_row("Water")
    assert row is not None
    # Empty effects placeholder
    assert "effects-none" in row
    # Safe threshold
    assert "threshold-safe" in row
    assert "Safe" in row
    # Group pill
    assert "Drink" in row


# ---------------------------------------------------------------------------
# Phase 3 — plant metabolism
# ---------------------------------------------------------------------------


PESTKILLER_YAML = """
- type: reagent
  id: PestKiller
  name: reagent-name-pestkiller
  desc: reagent-desc-pestkiller
  group: Botanical
  color: "#9e9886"
  plantMetabolism:
    - !type:PlantAdjustToxins
      amount: 4
    - !type:PlantAdjustPests
      amount: -6
  metabolisms:
    Bloodstream:
      effects:
      - !type:HealthChange
        damage:
          types:
            Poison: 3
"""


def test_plant_metabolism_renders_distinct_section() -> None:
    _reset_state()
    raw = _load_reagent(PESTKILLER_YAML)
    _install_reagent(raw)

    # Row has both bloodstream (Poison damage) and plant-effects sections.
    row = render._reagent_row("PestKiller")
    assert row is not None
    assert "plant-effects" in row
    assert "plant-tag" in row
    assert "kills pests" in row
    assert "raises plant toxin level by 4" in row
    # Bloodstream damage (ungated toxic) gets a Toxic pill.
    assert "threshold-toxic" in row or "max safe dose" in row

    # Detail view — has dedicated plant metabolism section heading.
    elem = ET.Element("GuideReagentEmbed", {"Reagent": "PestKiller"})
    card = render._render_reagent_embed(elem)
    assert "Plant metabolism" in card
    assert "Bloodstream effects" in card


# ---------------------------------------------------------------------------
# Phase 2 — microwave recipe Appliance column
# ---------------------------------------------------------------------------


def test_microwave_appliance_column() -> None:
    _reset_state()
    render._MICROWAVE_RECIPES["RecipeBun"] = {
        "id": "RecipeBun",
        "name": "bun recipe",
        "result": "FoodBreadBun",
        "time": 5,
        "group": "Breads",
        "solids": {"FoodDoughSlice": 1},
        "reagents": {},
        "appliance": "Microwave",
    }

    elem = ET.Element("GuideMicrowaveGroupEmbed", {"Group": "Breads"})
    html_out = render._render_microwave_group_embed(elem)
    # Header includes Appliance column
    assert "<th>Appliance</th>" in html_out
    # Row shows Microwave
    assert "recipe-appliance" in html_out
    assert ">Microwave<" in html_out
    # Existing columns still present
    assert "<th>Result</th>" in html_out
    assert "<th>Recipe</th>" in html_out
    assert "<th>Inputs</th>" in html_out
    assert "<th>Time</th>" in html_out


# ---------------------------------------------------------------------------
# Unknown effect fallback — must render literally, not silently drop
# ---------------------------------------------------------------------------


MYSTERY_YAML = """
- type: reagent
  id: Mystery
  name: reagent-name-mystery
  desc: reagent-desc-mystery
  group: Admin
  color: "#ff00ff"
  metabolisms:
    Bloodstream:
      effects:
      - !type:TotallyNewEffectTypeVS
        intensity: 42
        label: spooky
"""


def test_unknown_effect_falls_back_literally() -> None:
    _reset_state()
    raw = _load_reagent(MYSTERY_YAML)
    _install_reagent(raw)

    row = render._reagent_row("Mystery")
    assert row is not None
    # Type name and key=value both present
    assert "TotallyNewEffectTypeVS" in row
    assert "intensity=42" in row
    assert "label=spooky" in row


# ---------------------------------------------------------------------------
# Group column classifies reagents (Medicine / Toxin / Drink / Admin)
# ---------------------------------------------------------------------------


def test_group_pill_slug_normalization() -> None:
    _reset_state()
    raw = _load_reagent(MYSTERY_YAML)
    _install_reagent(raw)
    row = render._reagent_row("Mystery")
    assert row is not None
    # Admin group becomes an "admin" slug class.
    assert "reagent-group-admin" in row


# ---------------------------------------------------------------------------
# Smoke test: _fmt_num
# ---------------------------------------------------------------------------


def test_fmt_num_trims_zeros() -> None:
    assert render._fmt_num(1.5) == "1.5"
    assert render._fmt_num(2.0) == "2"
    assert render._fmt_num(-0.5) == "-0.5"
    assert render._fmt_num(0) == "0"
    assert render._fmt_num(0.25) == "0.25"


# ---------------------------------------------------------------------------
# vs-dnz — collapsible sidebar sections + partial-content nav
# ---------------------------------------------------------------------------


def _toy_entries() -> dict[str, dict]:
    """A tiny three-level entry tree for TOC / ancestor tests.

    SS14 -> Jobs -> Engineering -> Airlocks
                 -> Medical (leaf with no children)
    NewPlayer (root, leaf)
    """
    return {
        "SS14": {
            "id": "SS14",
            "name_key": "guide-entry-ss14",
            "text": "",
            "children": ["Jobs"],
            "priority": 1,
            "parent": None,
        },
        "Jobs": {
            "id": "Jobs",
            "name_key": "guide-entry-jobs",
            "text": "",
            "children": ["Engineering", "Medical"],
            "priority": 1,
            "parent": "SS14",
        },
        "Engineering": {
            "id": "Engineering",
            "name_key": "guide-entry-engineering",
            "text": "",
            "children": ["Airlocks"],
            "priority": 1,
            "parent": "Jobs",
        },
        "Airlocks": {
            "id": "Airlocks",
            "name_key": "guide-entry-airlocks",
            "text": "",
            "children": [],
            "priority": 1,
            "parent": "Engineering",
        },
        "Medical": {
            "id": "Medical",
            "name_key": "guide-entry-medical",
            "text": "",
            "children": [],
            "priority": 2,
            "parent": "Jobs",
        },
        "NewPlayer": {
            "id": "NewPlayer",
            "name_key": "guide-entry-newplayer",
            "text": "",
            "children": [],
            "priority": 0,
            "parent": None,
        },
    }


def _toy_labels() -> dict[str, str]:
    return {
        "guide-entry-ss14": "Space Station 14",
        "guide-entry-jobs": "Jobs",
        "guide-entry-engineering": "Engineering",
        "guide-entry-airlocks": "Airlocks",
        "guide-entry-medical": "Medical",
        "guide-entry-newplayer": "New Player",
    }


def test_build_toc_wraps_parents_in_details_with_section_id() -> None:
    """Parent entries (those with children) must render as
    <details data-section-id="..."> so JS can persist collapse state."""
    entries = _toy_entries()
    labels = _toy_labels()
    toc = render.build_toc(entries, labels, current="Airlocks")

    # SS14 is a parent (has Jobs) — must be wrapped in <details>
    assert '<details data-section-id="SS14">' in toc
    # Jobs is a parent — wrapped
    assert '<details data-section-id="Jobs">' in toc
    # Engineering is a parent — wrapped
    assert '<details data-section-id="Engineering">' in toc
    # Airlocks is a leaf — NOT wrapped in its own <details>
    assert '<details data-section-id="Airlocks">' not in toc
    # Every nav link gets data-nav-link for JS interception
    assert "data-nav-link" in toc
    # Active entry is marked with aria-current="page"
    assert 'aria-current="page"' in toc
    # Chevron button for parent-section toggling
    assert 'class="toc-toggle"' in toc


def test_build_toc_leaf_has_no_details_wrapper() -> None:
    """Root leafs (no children) render as plain <li><a>...</a></li>."""
    entries = _toy_entries()
    labels = _toy_labels()
    toc = render.build_toc(entries, labels, current=None)
    # NewPlayer is a root leaf — no <details>/<summary> overhead
    assert '<li><a href="NewPlayer.html" data-nav-link' in toc
    # No details wrapper for NewPlayer or Airlocks (leaves)
    assert 'data-section-id="NewPlayer"' not in toc
    assert 'data-section-id="Airlocks"' not in toc


def test_entry_ancestors_excludes_self() -> None:
    """The ancestor chain force-opens <details> above the active entry;
    the active entry itself must NOT appear in the chain (it's a leaf)."""
    entries = _toy_entries()
    assert render._entry_ancestors("Airlocks", entries) == [
        "Engineering",
        "Jobs",
        "SS14",
    ]
    assert render._entry_ancestors("NewPlayer", entries) == []
    assert render._entry_ancestors("SS14", entries) == []
    assert render._entry_ancestors(None, entries) == []
    assert render._entry_ancestors("UnknownEid", entries) == []


def test_page_template_has_inline_bootstrap_and_content_wrapper() -> None:
    """Every rendered page MUST carry:
    - an inline <head> bootstrap script that touches localStorage pre-paint
    - a <main id="content"> wrapper around the per-page body (partial-swap target)
    - a reference to guidebook-nav.js
    - collapse-all / expand-all sidebar buttons
    """
    html_out = render.PAGE_TEMPLATE.format(
        title="Demo",
        toc="<ul></ul>",
        crumbs='<a href="index.html">Guidebook</a>',
        body="<p>hello</p>",
        source="(demo)",
        ancestors_json="[]",
    )
    # Inline bootstrap: reads localStorage before paint
    assert "vs14-guidebook-nav-state" in html_out
    assert "localStorage.getItem" in html_out
    # Content wrapper that the partial-swap JS targets
    assert '<main id="content"' in html_out
    # Partial-nav JS reference
    assert 'src="guidebook-nav.js"' in html_out
    # Sidebar controls
    assert 'data-toc-action="expand-all"' in html_out
    assert 'data-toc-action="collapse-all"' in html_out
    # Active-ancestors array injection
    assert "window.__VS14_ACTIVE_ANCESTORS" in html_out


def test_guidebook_nav_js_constant_has_required_behavior() -> None:
    """The emitted JS must implement the spec'd pipeline: fetch + swap
    #content, pushState, popstate handling, same-origin check, localStorage
    persistence on toggle, and collapse/expand-all actions."""
    js = render.GUIDEBOOK_NAV_JS
    # localStorage key matches the bootstrap's key
    assert "vs14-guidebook-nav-state" in js
    # Fetch-and-swap pipeline
    assert "fetch(" in js
    assert "pushState" in js
    assert "popstate" in js
    # Content target
    assert 'getElementById("content")' in js
    # nav:loaded custom event for external re-init
    assert "nav:loaded" in js
    # Collapse/expand-all wiring
    assert "expand-all" in js
    assert "collapse-all" in js
    # Same-origin enforcement
    assert "origin" in js
    # Error fallback to full-page reload
    assert "window.location.href" in js


# ---------------------------------------------------------------------------
# vs-05o.1 — entity stat blocks under GuideEntityEmbed
# ---------------------------------------------------------------------------


def _entity(
    eid: str,
    *,
    parent: str | list[str] | None = None,
    components: list[dict] | None = None,
    sprite_rsi: str | None = None,
    state: str | None = None,
) -> dict:
    """Construct the per-entity dict that `load_entity_sprites` produces.

    Mirrors the shape the production loader emits so `_walk_parents` and
    `_resolve_entity_components` can walk the synthetic fixture.
    """
    stat_components: dict[str, dict] = {}
    for comp in components or []:
        ctype = comp.get("type")
        if isinstance(ctype, str) and ctype in render._STAT_COMPONENT_TYPES:
            stat_components.setdefault(ctype, comp)
    return {
        "parent": parent,
        "sprite_rsi": sprite_rsi,
        "state": state,
        "abstract": False,
        "stat_components": stat_components,
    }


def test_mob_max_health_inherits_from_parent_chain() -> None:
    """MobHuman defines thresholds; a syndicate-agent child inherits them."""
    entities = {
        "MobHuman": _entity(
            "MobHuman",
            components=[
                {
                    "type": "MobThresholds",
                    "thresholds": {0: "Alive", 100: "Critical", 200: "Dead"},
                },
                {"type": "Damageable", "damageContainer": "Biological"},
            ],
        ),
        "MobHumanSyndicateAgent": _entity(
            "MobHumanSyndicateAgent",
            parent="MobHuman",
            components=[],
        ),
    }
    rows = render._entity_stat_rows("MobHumanSyndicateAgent", entities)
    row_map = dict(rows)
    assert row_map["max health"] == "200"
    assert row_map["crit threshold"] == "100"
    assert row_map["damage container"] == "Biological"


def test_solution_container_capacity_renders_per_solution() -> None:
    """A beaker with a single `beaker: { maxVol: 50 }` renders one row."""
    entities = {
        "Beaker": _entity(
            "Beaker",
            components=[
                {
                    "type": "SolutionContainerManager",
                    "solutions": {"beaker": {"maxVol": 50}},
                },
            ],
        ),
    }
    rows = render._entity_stat_rows("Beaker", entities)
    row_map = dict(rows)
    assert row_map["beaker capacity"] == "50u"


def test_storage_grid_area_becomes_slot_count() -> None:
    """A `grid: ["0,0,9,3"]` is a 10x4 rectangle = 40 slots."""
    entities = {
        "BigBag": _entity(
            "BigBag",
            components=[
                {
                    "type": "Storage",
                    "grid": ["0,0,9,3"],
                    "maxItemSize": "Huge",
                },
            ],
        ),
    }
    rows = render._entity_stat_rows("BigBag", entities)
    row_map = dict(rows)
    assert row_map["storage capacity"] == "40 slot(s)"
    assert row_map["max item size"] == "Huge"


def test_power_cell_battery_charge_rows() -> None:
    """Battery rows: max charge + starting charge when different from max."""
    entities = {
        "PowerCellSmall": _entity(
            "PowerCellSmall",
            components=[
                {"type": "PowerCell"},
                {"type": "Battery", "maxCharge": 360, "startingCharge": 360},
            ],
        ),
        "PowerCellSmallPrinted": _entity(
            "PowerCellSmallPrinted",
            parent="PowerCellSmall",
            components=[
                {"type": "Battery", "maxCharge": 360, "startingCharge": 0},
            ],
        ),
    }
    # Full cell: only max charge (starting == max)
    rows = dict(render._entity_stat_rows("PowerCellSmall", entities))
    assert rows["max charge"] == "360 J"
    assert "starting charge" not in rows
    # Printed empty: both rows
    rows = dict(render._entity_stat_rows("PowerCellSmallPrinted", entities))
    assert rows["max charge"] == "360 J"
    assert rows["starting charge"] == "0 J"


def test_armor_coefficients_render_interpretively() -> None:
    """Armor coefficients: 0.8 = 20% reduction; 0 = immune; 1.2 = +20%."""
    _reset_state()
    entities = {
        "ClothingHeadHelmet": _entity(
            "ClothingHeadHelmet",
            components=[
                {
                    "type": "Armor",
                    "modifiers": {
                        "coefficients": {
                            "Blunt": 0.8,
                            "Radiation": 0,
                            "Heat": 1.2,
                        },
                    },
                },
            ],
        ),
    }
    rows = dict(render._entity_stat_rows("ClothingHeadHelmet", entities))
    # Blunt: 1.0 - 0.8 = 20% reduction
    assert "20% reduction" in rows["Blunt armor"]
    # Radiation: coefficient 0 = immune
    assert rows["Radiation armor"] == "immune"
    # Heat: 1.2 > 1.0 = +20% vulnerability
    assert "+20%" in rows["Heat armor"]


def test_clothing_speed_modifier_surfaces_slowdown() -> None:
    """ClothingSpeedModifier with sprintModifier 0.9 → 10% slower row."""
    entities = {
        "ClothingBackDuffel": _entity(
            "ClothingBackDuffel",
            components=[
                {
                    "type": "ClothingSpeedModifier",
                    "walkModifier": 1,
                    "sprintModifier": 0.9,
                },
            ],
        ),
    }
    rows = dict(render._entity_stat_rows("ClothingBackDuffel", entities))
    # walkModifier == 1 is neutral, not surfaced
    assert "walk speed" not in rows
    # sprintModifier 0.9 = 10% slower
    assert "10% slower" in rows["sprint speed"]


def test_decorative_entity_has_no_stats_block() -> None:
    """A poster entity with no stat components yields an empty row list."""
    entities = {
        "PosterBase": _entity(
            "PosterBase",
            components=[],
        ),
        "PosterContrabandSyndicateRecruitment": _entity(
            "PosterContrabandSyndicateRecruitment",
            parent="PosterBase",
            components=[],
        ),
    }
    rows = render._entity_stat_rows(
        "PosterContrabandSyndicateRecruitment", entities
    )
    assert rows == []
    # And the rendered block is an empty string → handler stays sprite-only.
    block = render._render_entity_stats_block(
        "PosterContrabandSyndicateRecruitment", entities
    )
    assert block == ""


def test_damage_container_only_is_treated_as_decorative() -> None:
    """An entity whose only stat component is `Damageable` (posters,
    static structures) should suppress the block — a lone "damage
    container: StructuralInorganic" row is low-value noise."""
    entities = {
        "PosterBase": _entity(
            "PosterBase",
            components=[
                {
                    "type": "Damageable",
                    "damageContainer": "StructuralInorganic",
                },
            ],
        ),
    }
    rows = render._entity_stat_rows("PosterBase", entities)
    assert rows == []
    # Containers with both Damageable AND other stats still render.
    entities_beaker = {
        "Beaker": _entity(
            "Beaker",
            components=[
                {"type": "Damageable", "damageContainer": "Inorganic"},
                {
                    "type": "SolutionContainerManager",
                    "solutions": {"beaker": {"maxVol": 50}},
                },
            ],
        ),
    }
    rows = dict(render._entity_stat_rows("Beaker", entities_beaker))
    assert rows["damage container"] == "Inorganic"
    assert rows["beaker capacity"] == "50u"


def test_stats_block_wraps_in_collapsible_details() -> None:
    """Stat block must render as <details class=entity-stats> with a table."""
    entities = {
        "MobDog": _entity(
            "MobDog",
            components=[
                {
                    "type": "MobThresholds",
                    "thresholds": {0: "Alive", 50: "Dead"},
                },
            ],
        ),
    }
    block = render._render_entity_stats_block("MobDog", entities)
    assert '<details class="entity-stats">' in block
    assert "<summary" in block
    assert "<table" in block
    assert "<th>max health</th>" in block
    assert "<td>50</td>" in block


# ---------------------------------------------------------------------------
# Harmless-unreachable helper: allow `python3 test_render.py` as a runner
# ---------------------------------------------------------------------------


def _main() -> int:
    tests = [
        name
        for name in sorted(globals())
        if name.startswith("test_") and callable(globals()[name])
    ]
    failures = 0
    for name in tests:
        try:
            globals()[name]()
        except AssertionError as exc:
            failures += 1
            print(f"FAIL {name}: {exc}")
        except Exception as exc:
            failures += 1
            print(f"ERROR {name}: {exc!r}")
        else:
            print(f"ok   {name}")
    print(f"\n{len(tests) - failures}/{len(tests)} passed")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(_main())
