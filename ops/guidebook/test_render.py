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
