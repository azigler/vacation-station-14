#!/usr/bin/env python3
"""Render the SS14 in-game Guidebook to static HTML.

Inputs (resolved from --repo):
  Resources/Prototypes/Guidebook/*.yml     — `guideEntry` tree (ids + children)
  Resources/Locale/en-US/guidebook/guides.ftl — `guide-entry-<id> = <label>`
  Resources/ServerInfo/Guidebook/**/*.xml  — per-page document bodies

Output (into --out):
  index.html                               — sidebar + landing page
  <id>.html                                — one file per guide entry

The XML bodies are authored for SS14's in-game `Document` control and mix
raw markdown-ish text with SS14-specific XML tags. We implement a
deliberately-small subset (enough for a readable static site):

  - Markdown-like inline: [bold], [italic], [color=NAME]...[/color]
  - Headings:   `# ...` and `## ...` at line start
  - List items: `- ...` at line start
  - Fenced tags: [keybind="X"], [textlink="t" link="id"], [protodata="..."/]
  - XML containers: <Box>, <Table>, <ColorBox> — flatten children
  - Entity embeds: <GuideEntityEmbed Entity="X" Caption="Y"/> → pill showing
    the entity id (no sprite rendering in v1)
  - Cross-links: `link="OtherPage"` resolves to <OtherPage>.html if the id
    exists, else falls back to a plain text label.

Unknown tags are kept verbatim (wrapped in a visible debug pill) so
missing support is obvious but doesn't break the page.

v1 scope: ugly-but-correct. Sprite rendering is intentionally deferred.

Interpretive language for reagent effects (vs-05o) mirrors the SS14
community wiki's voice — "heals 2 brute damage per unit", "max safe
dose 10u" — rather than dumping literal engine primitives. Inspiration:

  - https://wiki.spacestation14.com/wiki/Medical
  - https://wiki.spacestation14.com/wiki/Guide_to_Medical
  - https://wiki.spacestation14.com/wiki/Reagents
  - https://wiki.spacestation14.com/wiki/Medicine
"""

from __future__ import annotations

import argparse
import html
import json
import re
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import yaml

try:
    from PIL import Image  # type: ignore[import-not-found]

    _PIL_AVAILABLE = True
except ImportError:  # pragma: no cover - environment-dependent
    Image = None  # type: ignore[assignment]
    _PIL_AVAILABLE = False

# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------


def load_entries(repo: Path) -> dict[str, dict]:
    """Parse `guideEntry` prototypes into a dict keyed by id.

    Each entry: {id, name, text (xml path), children, parent, priority}.
    """
    proto_dir = repo / "Resources" / "Prototypes" / "Guidebook"
    entries: dict[str, dict] = {}
    for yml in sorted(proto_dir.glob("*.yml")):
        docs = yaml.safe_load(yml.read_text(encoding="utf-8")) or []
        for raw in docs:
            if not isinstance(raw, dict) or raw.get("type") != "guideEntry":
                continue
            eid = raw["id"]
            entries[eid] = {
                "id": eid,
                "name_key": raw.get("name", ""),
                "text": raw.get("text", ""),
                "children": list(raw.get("children", []) or []),
                "priority": int(raw.get("priority", 10)),
                "parent": None,
            }
    for eid, entry in entries.items():
        for child in entry["children"]:
            if child in entries:
                entries[child]["parent"] = eid
    return entries


def load_labels(repo: Path) -> dict[str, str]:
    """Parse `guide-entry-<key> = <label>` from the guidebook fluent file."""
    ftl = repo / "Resources" / "Locale" / "en-US" / "guidebook" / "guides.ftl"
    labels: dict[str, str] = {}
    if not ftl.exists():
        return labels
    current_key: str | None = None
    for line in ftl.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^([a-zA-Z0-9_-]+)\s*=\s*(.*)$", line)
        if m:
            current_key = m.group(1)
            labels[current_key] = m.group(2).strip()
        elif current_key and line.startswith(" "):
            labels[current_key] += " " + line.strip()
    return labels


def load_all_locale(repo: Path) -> dict[str, str]:
    """Scan every `.ftl` file under en-US and return a flat `key → value` map.

    Used to resolve reagent / law / tech display names. Fluent attribute
    lines (`.title = Foo`) are ignored — we only need top-level messages.
    Duplicate keys keep the first occurrence, matching Fluent's behavior
    of failing loud in-game; here we just stabilize the web build.
    """
    out: dict[str, str] = {}
    ftl_root = repo / "Resources" / "Locale" / "en-US"
    if not ftl_root.is_dir():
        return out
    key_re = re.compile(r"^([a-zA-Z][a-zA-Z0-9_-]*)\s*=\s*(.*)$")
    for ftl in ftl_root.rglob("*.ftl"):
        try:
            text = ftl.read_text(encoding="utf-8")
        except OSError:
            continue
        current: str | None = None
        for raw in text.splitlines():
            line = raw.rstrip()
            if not line or line.lstrip().startswith("#"):
                current = None
                continue
            m = key_re.match(line)
            if m:
                key = m.group(1)
                val = m.group(2).strip()
                current = key
                out.setdefault(key, val)
            elif current and line.startswith((" ", "\t")):
                stripped = line.strip()
                if stripped.startswith("."):
                    # Fluent attribute line — ignore for now
                    current = None
                    continue
                out[current] = (out.get(current, "") + " " + stripped).strip()
            else:
                current = None
    return out


def _strip_fluent_markup(s: str) -> str:
    """Remove Fluent placeables and SS14 bracket markup for plain display.

    Fluent strings can contain `{ $var }` placeables and `{ -term }` terms.
    SS14 strings sometimes mix in `[bold]`, `[color=...]`, etc. For table
    cells we want a readable plain-text fallback — drop the markup rather
    than render half of it.
    """
    s = re.sub(r"\{\s*\$([a-zA-Z_][a-zA-Z0-9_-]*)\s*\}", r"\1", s)
    s = re.sub(r"\{[^{}]*\}", "", s)
    s = re.sub(r"\[/?[a-zA-Z][^\]]{0,40}\]", "", s)
    return s.strip()


# ---------------------------------------------------------------------------
# Reagent / recipe / technology / lawset scans
# ---------------------------------------------------------------------------


def _extract_bloodstream_effects(raw: dict) -> tuple[list[dict], float | None]:
    """Pull Bloodstream metabolism effects + metabolismRate off a reagent doc.

    The YAML mapping looks like::

        metabolisms:
          Bloodstream:
            metabolismRate: 0.5
            effects:
              - !type:HealthChange { ... }
              - !type:Jitter { ... }

    `!type:Foo` tags are stripped by `_EntityYamlLoader` so effects arrive as
    plain dicts with the `!type:` suffix preserved in an injected `__type__`
    key — except `_EntityYamlLoader` doesn't do that injection. Instead, we
    re-parse the raw YAML text with a tag-recording loader in a later pass
    for a richer structure… or we use a simpler trick: scan the pre-load
    text for `!type:X` lines.

    For now, effects are dicts without their `!type:` tag (the loader
    discarded it). To recover the type we re-scan the YAML text source
    externally — see `_tag_for_effect`. That's messy; cleaner is to extend
    `_EntityYamlLoader` to record the tag under a private key. We do that
    via `_TagRecordingLoader` which this function uses when called from
    `load_reagents`.
    """
    metabolisms = raw.get("metabolisms") or {}
    if not isinstance(metabolisms, dict):
        return [], None
    blood = metabolisms.get("Bloodstream") or {}
    if not isinstance(blood, dict):
        return [], None
    rate = blood.get("metabolismRate")
    rate_val: float | None = None
    try:
        if rate is not None:
            rate_val = float(rate)
    except (TypeError, ValueError):
        rate_val = None
    effects = blood.get("effects") or []
    if not isinstance(effects, list):
        effects = []
    return [e for e in effects if isinstance(e, dict)], rate_val


def _extract_plant_effects(raw: dict) -> list[dict]:
    """Pull the `plantMetabolism` array off a reagent doc (or `[]`)."""
    pm = raw.get("plantMetabolism") or []
    if not isinstance(pm, list):
        return []
    return [e for e in pm if isinstance(e, dict)]


class _TagRecordingLoader(yaml.SafeLoader):
    """SafeLoader that stores SS14 `!type:Foo` tags under `__type__`.

    `_EntityYamlLoader` silently strips the tag; for reagent effect parsing
    we need to know whether an entry is `HealthChange`, `Jitter`, etc. This
    loader keeps `tag_suffix` around on mapping-valued nodes, and leaves
    scalar `!type:Foo` entries as empty dicts with the type recorded.
    """


def _record_type_tag(
    loader: yaml.Loader, tag_suffix: str, node: yaml.Node
) -> object:
    # Only `!type:Foo` tags are interesting; anything else (e.g. Fluent
    # sentinel tags) we treat like `_EntityYamlLoader` and drop quietly.
    is_type = tag_suffix.startswith("type:")
    type_name = tag_suffix[len("type:") :] if is_type else None
    if isinstance(node, yaml.ScalarNode):
        # Scalar-shaped `!type:Foo` → a zero-arg effect (e.g. `- !type:Drunk`).
        if is_type:
            return {"__type__": type_name}
        return loader.construct_scalar(node)
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node, deep=True)
    if isinstance(node, yaml.MappingNode):
        mapping = loader.construct_mapping(node, deep=True)
        if is_type and isinstance(mapping, dict):
            mapping["__type__"] = type_name
        return mapping
    return None


_TagRecordingLoader.add_multi_constructor("!", _record_type_tag)
_TagRecordingLoader.add_multi_constructor(
    "tag:yaml.org,2002:", _record_type_tag
)


def load_reagents(repo: Path) -> dict[str, dict]:
    """Scan Resources/Prototypes/Reagents/**/*.yml for `type: reagent`.

    Returns id → {name_key, desc_key, group, color, physical_desc_key,
    flavor, bloodstream_effects, plant_effects, metabolism_rate}. Name /
    desc are locale keys, resolved later via `load_all_locale`. Effects
    are dicts carrying their `!type:` tag under the `__type__` key, for
    downstream rendering.
    """
    out: dict[str, dict] = {}
    proto_dir = repo / "Resources" / "Prototypes" / "Reagents"
    if not proto_dir.is_dir():
        return out
    for yml in proto_dir.rglob("*.yml"):
        try:
            docs = yaml.load(
                yml.read_text(encoding="utf-8"), Loader=_TagRecordingLoader
            )
        except yaml.YAMLError:
            continue
        if not isinstance(docs, list):
            continue
        for raw in docs:
            if not isinstance(raw, dict):
                continue
            if raw.get("type") != "reagent":
                continue
            rid = raw.get("id")
            if not isinstance(rid, str) or not rid:
                continue
            effects, rate = _extract_bloodstream_effects(raw)
            out[rid] = {
                "id": rid,
                "name_key": raw.get("name") or f"reagent-name-{rid.lower()}",
                "desc_key": raw.get("desc") or f"reagent-desc-{rid.lower()}",
                "physical_desc_key": raw.get("physicalDesc"),
                "flavor": raw.get("flavor"),
                "group": raw.get("group") or "Unknown",
                "color": raw.get("color"),
                "bloodstream_effects": effects,
                "plant_effects": _extract_plant_effects(raw),
                "metabolism_rate": rate,
            }
    return out


def load_microwave_recipes(repo: Path) -> dict[str, dict]:
    """Scan cooking recipes for `type: microwaveMealRecipe`.

    Returns id → {name, result, time, group, solids, reagents, appliance}.
    `solids` and `reagents` are dicts of proto-id → integer count. The
    `appliance` field is hardcoded to "Microwave" today — the embed column
    exists so future loaders (grill, oven, deep fryer, if SS14 adds them)
    can populate it without a schema change.
    """
    out: dict[str, dict] = {}
    proto_dir = repo / "Resources" / "Prototypes" / "Recipes" / "Cooking"
    if not proto_dir.is_dir():
        return out
    for yml in proto_dir.rglob("*.yml"):
        try:
            docs = yaml.load(
                yml.read_text(encoding="utf-8"), Loader=_EntityYamlLoader
            )
        except yaml.YAMLError:
            continue
        if not isinstance(docs, list):
            continue
        for raw in docs:
            if not isinstance(raw, dict):
                continue
            if raw.get("type") != "microwaveMealRecipe":
                continue
            rid = raw.get("id")
            if not isinstance(rid, str) or not rid:
                continue
            solids = raw.get("solids") or {}
            reagents = raw.get("reagents") or {}
            if not isinstance(solids, dict):
                solids = {}
            if not isinstance(reagents, dict):
                reagents = {}
            out[rid] = {
                "id": rid,
                "name": raw.get("name") or rid,
                "result": raw.get("result"),
                "time": raw.get("time"),
                "group": raw.get("group") or "Other",
                "solids": dict(solids),
                "reagents": dict(reagents),
                "appliance": "Microwave",
            }
    return out


def load_metamorph_recipes(repo: Path) -> dict[str, dict]:
    """Scan for `type: metamorphRecipe` — food sequence completion recipes.

    Metamorph recipes are how SS14 turns a multi-layer food sequence (e.g.
    burger stack with N ingredient tags) into a finished dish. They have
    no guidebook embed today (the in-game guide doesn't surface them)
    but we index them so a future `GuideMetamorphGroupEmbed` can ship
    without a loader change. See docs/guidebook-parity.md.

    Returns id → {key, result, rules}.
    """
    out: dict[str, dict] = {}
    proto_dir = repo / "Resources" / "Prototypes" / "Recipes" / "Cooking"
    if not proto_dir.is_dir():
        return out
    for yml in proto_dir.rglob("*.yml"):
        try:
            docs = yaml.load(
                yml.read_text(encoding="utf-8"), Loader=_EntityYamlLoader
            )
        except yaml.YAMLError:
            continue
        if not isinstance(docs, list):
            continue
        for raw in docs:
            if not isinstance(raw, dict):
                continue
            if raw.get("type") != "metamorphRecipe":
                continue
            rid = raw.get("id")
            if not isinstance(rid, str) or not rid:
                continue
            out[rid] = {
                "id": rid,
                "key": raw.get("key"),
                "result": raw.get("result"),
                "rules": list(raw.get("rules") or []),
            }
    return out


def load_research(repo: Path) -> tuple[dict[str, dict], dict[str, dict]]:
    """Scan Resources/Prototypes/Research for disciplines + technologies.

    Returns (disciplines, technologies) where each value is a dict keyed
    by id. Technologies record their discipline + tier + cost.
    """
    disciplines: dict[str, dict] = {}
    technologies: dict[str, dict] = {}
    proto_dir = repo / "Resources" / "Prototypes" / "Research"
    if not proto_dir.is_dir():
        return disciplines, technologies
    for yml in proto_dir.rglob("*.yml"):
        try:
            docs = yaml.load(
                yml.read_text(encoding="utf-8"), Loader=_EntityYamlLoader
            )
        except yaml.YAMLError:
            continue
        if not isinstance(docs, list):
            continue
        for raw in docs:
            if not isinstance(raw, dict):
                continue
            kind = raw.get("type")
            rid = raw.get("id")
            if not isinstance(rid, str) or not rid:
                continue
            if kind == "techDiscipline":
                disciplines[rid] = {
                    "id": rid,
                    "name_key": raw.get("name") or rid,
                    "color": raw.get("color"),
                }
            elif kind == "technology":
                technologies[rid] = {
                    "id": rid,
                    "name_key": raw.get("name") or rid,
                    "discipline": raw.get("discipline"),
                    "tier": raw.get("tier"),
                    "cost": raw.get("cost"),
                }
    return disciplines, technologies


def load_lawsets(repo: Path) -> tuple[dict[str, dict], dict[str, dict]]:
    """Scan for `type: siliconLawset` and `type: siliconLaw` prototypes.

    Returns (lawsets, laws). Lawsets record ordered law-id list + name.
    Laws record order + lawString (a locale key).
    """
    lawsets: dict[str, dict] = {}
    laws: dict[str, dict] = {}
    proto_dir = repo / "Resources" / "Prototypes"
    if not proto_dir.is_dir():
        return lawsets, laws
    for yml in proto_dir.rglob("*.yml"):
        # Fast-path filter: most yml files won't have lawsets.
        try:
            head = yml.read_text(encoding="utf-8")
        except OSError:
            continue
        if "type: siliconLaw" not in head and "type: siliconLawset" not in head:
            continue
        try:
            docs = yaml.load(head, Loader=_EntityYamlLoader)
        except yaml.YAMLError:
            continue
        if not isinstance(docs, list):
            continue
        for raw in docs:
            if not isinstance(raw, dict):
                continue
            kind = raw.get("type")
            rid = raw.get("id")
            if not isinstance(rid, str) or not rid:
                continue
            if kind == "siliconLaw":
                laws[rid] = {
                    "id": rid,
                    "order": raw.get("order", 0),
                    "law_string_key": raw.get("lawString"),
                }
            elif kind == "siliconLawset":
                lawsets[rid] = {
                    "id": rid,
                    "name_key": raw.get("name") or rid,
                    "laws": list(raw.get("laws") or []),
                    "obeys_to_key": raw.get("obeysTo"),
                }
    return lawsets, laws


# ---------------------------------------------------------------------------
# Entity sprite resolution (vs-mlg)
# ---------------------------------------------------------------------------
#
# Entity prototype YAMLs use SS14-specific `!type:Foo` YAML tags on mappings
# and sequences. yaml.SafeLoader rejects unknown tags, so we register a
# multi-constructor that strips the tag and loads the child value normally.
# We don't care about the tag's semantic meaning — only the raw fields we
# inspect (id, parent, components[].type == Sprite, sprite, state, layers).


class _EntityYamlLoader(yaml.SafeLoader):
    """SafeLoader that tolerates SS14 `!type:Foo` tags by ignoring them."""


def _ignore_tag(
    loader: yaml.Loader, tag_suffix: str, node: yaml.Node
) -> object:
    if isinstance(node, yaml.ScalarNode):
        return loader.construct_scalar(node)
    if isinstance(node, yaml.SequenceNode):
        return loader.construct_sequence(node, deep=True)
    if isinstance(node, yaml.MappingNode):
        return loader.construct_mapping(node, deep=True)
    return None


_EntityYamlLoader.add_multi_constructor("!", _ignore_tag)
_EntityYamlLoader.add_multi_constructor("tag:yaml.org,2002:", _ignore_tag)


def load_entity_sprites(repo: Path) -> dict[str, dict]:
    """Scan entity prototypes; return id → {parent, sprite_rsi, state}.

    Walks Resources/Prototypes/**/*.yml, picking up documents whose
    `type: entity` (prototype-like shape). For each, records:
      - parent: str | list[str] | None
      - sprite_rsi: RSI path (relative to Resources/Textures), or None
      - state: state name within the RSI, or None
      - abstract: whether the entity is abstract

    The renderer later walks the parent chain to inherit missing
    sprite/state fields.
    """
    proto_dir = repo / "Resources" / "Prototypes"
    out: dict[str, dict] = {}
    if not proto_dir.is_dir():
        return out

    for yml in proto_dir.rglob("*.yml"):
        try:
            docs = yaml.load(
                yml.read_text(encoding="utf-8"), Loader=_EntityYamlLoader
            )
        except yaml.YAMLError:
            continue
        if not isinstance(docs, list):
            continue
        for raw in docs:
            if not isinstance(raw, dict):
                continue
            if raw.get("type") != "entity":
                continue
            eid = raw.get("id")
            if not isinstance(eid, str) or not eid:
                continue
            sprite_rsi: str | None = None
            state: str | None = None
            components = raw.get("components") or []
            if isinstance(components, list):
                for comp in components:
                    if not isinstance(comp, dict):
                        continue
                    if comp.get("type") != "Sprite":
                        continue
                    spr = comp.get("sprite")
                    if isinstance(spr, str):
                        sprite_rsi = spr
                    st = comp.get("state")
                    if isinstance(st, str):
                        state = st
                    # Fallback: first layer's state if top-level state
                    # is missing. v2 ignores layer compositing per scope.
                    if state is None:
                        layers = comp.get("layers")
                        if isinstance(layers, list):
                            for layer in layers:
                                if isinstance(layer, dict) and isinstance(
                                    layer.get("state"), str
                                ):
                                    state = layer["state"]
                                    if not sprite_rsi and isinstance(
                                        layer.get("sprite"), str
                                    ):
                                        sprite_rsi = layer["sprite"]
                                    break
                    break  # only first Sprite component
            out[eid] = {
                "parent": raw.get("parent"),
                "sprite_rsi": sprite_rsi,
                "state": state,
                "abstract": bool(raw.get("abstract", False)),
            }
    return out


def _walk_parents(entity_id: str, entities: dict[str, dict]) -> list[str]:
    """Return the parent chain for entity_id, nearest ancestor first.

    SS14 supports single-parent (`parent: Foo`) and multi-parent
    (`parent: [Foo, Bar]`) declarations. For multi-parent we walk each
    branch in order; most multi-parents are mix-ins that don't affect
    Sprite, so the Sprite-bearing ancestor is usually on branch 0.
    """
    chain: list[str] = []
    seen: set[str] = {entity_id}
    stack: list[str] = [entity_id]
    while stack:
        cur = stack.pop(0)
        ent = entities.get(cur)
        if ent is None:
            continue
        parent = ent.get("parent")
        parents: list[str] = []
        if isinstance(parent, str):
            parents = [parent]
        elif isinstance(parent, list):
            parents = [p for p in parent if isinstance(p, str)]
        for p in parents:
            if p in seen:
                continue
            seen.add(p)
            chain.append(p)
            stack.append(p)
    return chain


def resolve_sprite(
    entity_id: str, entities: dict[str, dict]
) -> tuple[str, str] | None:
    """Return (rsi_path, state) for entity_id, walking parents.

    RSI path is relative to Resources/Textures. Returns None if the
    entity has no resolvable sprite (e.g. no Sprite component anywhere
    in the inheritance chain).
    """
    ent = entities.get(entity_id)
    if ent is None:
        return None
    rsi = ent.get("sprite_rsi")
    state = ent.get("state")
    if rsi and state:
        return (rsi, state)
    # Walk parents until we have both fields
    for ancestor_id in _walk_parents(entity_id, entities):
        anc = entities[ancestor_id]
        if not rsi and anc.get("sprite_rsi"):
            rsi = anc["sprite_rsi"]
        if not state and anc.get("state"):
            state = anc["state"]
        if rsi and state:
            break
    if not rsi:
        return None
    # Some entities declare `sprite:` without a `state:` — SS14 defaults
    # to the first state in the RSI. We'll resolve that at PNG time.
    return (rsi, state or "")


def _extract_sprite_png(
    repo: Path,
    rsi_rel: str,
    state: str,
    dest: Path,
) -> bool:
    """Extract a single-frame PNG for rsi/state into dest. Returns True on success.

    - Reads Resources/Textures/<rsi_rel>/meta.json to find the state's
      `directions` and the RSI's canonical `size` (per-frame dimensions).
    - If the state is non-directional (directions omitted or 1) the PNG
      on disk is already a single frame; just copy it.
    - If directional, the PNG is a grid of directional frames laid out
      left-to-right, top-to-bottom. We slice the first frame (index 0,
      which corresponds to `South` in SS14 convention) using Pillow.
      If Pillow isn't available, we fall back to copying the whole
      spritesheet — readable-ish for 4-dir icons, visibly multi-frame
      for 8-dir ones. The caller logs a warning in that case.
    """
    rsi_dir = repo / "Resources" / "Textures" / rsi_rel
    meta_path = rsi_dir / "meta.json"
    if not meta_path.is_file():
        return False
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False

    states = meta.get("states") or []
    if not state:
        # Use the first state if unspecified
        if not states or not isinstance(states[0], dict):
            return False
        state = states[0].get("name") or ""
        if not state:
            return False

    state_meta: dict | None = None
    for s in states:
        if isinstance(s, dict) and s.get("name") == state:
            state_meta = s
            break
    if state_meta is None:
        return False

    png_path = rsi_dir / f"{state}.png"
    if not png_path.is_file():
        return False

    directions = int(state_meta.get("directions", 1) or 1)
    if directions <= 1 or not _PIL_AVAILABLE:
        # Copy as-is. For directional states without Pillow we accept a
        # slightly degraded render rather than crashing the build.
        try:
            shutil.copyfile(png_path, dest)
        except OSError:
            return False
        return True

    size = meta.get("size") or {}
    try:
        w = int(size["x"])
        h = int(size["y"])
    except (KeyError, TypeError, ValueError):
        return False

    try:
        with Image.open(png_path) as img:  # type: ignore[union-attr]
            img.load()
            # First frame is top-left (South direction).
            crop = img.crop((0, 0, w, h))
            crop.save(dest, format="PNG", optimize=True)
    except (OSError, ValueError):
        return False
    return True


class SpriteCache:
    """Memoize entity-id → output sprite path (or None on failure).

    The cache guarantees each entity's PNG is extracted at most once
    per build — critical for the 575-embed guidebook where popular
    entities appear on many pages.
    """

    def __init__(
        self,
        repo: Path,
        out_dir: Path,
        entities: dict[str, dict],
    ) -> None:
        self.repo = repo
        self.out_dir = out_dir  # e.g. <out>/sprites
        self.entities = entities
        self._resolved: dict[str, str | None] = {}
        self._warned_no_pil = False
        self.out_dir.mkdir(parents=True, exist_ok=True)

    def get(self, entity_id: str) -> str | None:
        """Return the basename (e.g. `Foo.png`) of the sprite, or None."""
        if entity_id in self._resolved:
            return self._resolved[entity_id]
        result = self._resolve(entity_id)
        self._resolved[entity_id] = result
        return result

    def _resolve(self, entity_id: str) -> str | None:
        spec = resolve_sprite(entity_id, self.entities)
        if spec is None:
            return None
        rsi, state = spec
        # Sanitize entity_id for filesystem: SS14 ids are PascalCase
        # ASCII in practice, but be defensive.
        safe_id = re.sub(r"[^A-Za-z0-9_.-]", "_", entity_id)
        dest = self.out_dir / f"{safe_id}.png"
        if dest.exists():
            return dest.name
        ok = _extract_sprite_png(self.repo, rsi, state, dest)
        if not ok:
            return None
        if not _PIL_AVAILABLE and not self._warned_no_pil:
            print(
                "  WARN: Pillow not installed — directional sprites will "
                "render as full spritesheets. `apt install python3-pil`.",
                file=sys.stderr,
            )
            self._warned_no_pil = True
        return dest.name


# ---------------------------------------------------------------------------
# Inline text → HTML
# ---------------------------------------------------------------------------


_INLINE_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"\[bold\](.*?)\[/bold\]", re.S), r"<strong>\1</strong>"),
    (re.compile(r"\[italic\](.*?)\[/italic\]", re.S), r"<em>\1</em>"),
    (
        re.compile(r"\[color=([^\]]+)\](.*?)\[/color\]", re.S),
        lambda m: (
            f'<span style="color:{_safe_color(m.group(1))}">{m.group(2)}</span>'
        ),
    ),
]


_COLOR_OK = re.compile(r"^#?[A-Za-z0-9]+$")


def _safe_color(raw: str) -> str:
    raw = raw.strip()
    if _COLOR_OK.match(raw):
        return html.escape(raw)
    return "inherit"


def render_inline(text: str, entry_ids: set[str]) -> str:
    """Escape HTML-special chars, then re-expand known markdown-ish tags.

    Rules applied in order:
      1. html-escape the raw text first
      2. [bold] / [italic] / [color=X]
      3. [keybind="X"] → <kbd>X</kbd>
      4. [textlink="label" link="id"] → anchor (if id known) else label
      5. [protodata=...] → fixed "[data]" placeholder
      6. bare <GuideEntityEmbed ... /> that slipped through → plain pill
    """
    # html.escape with quote=False leaves `"` intact so bracket-tag regexes
    # can still see the original attribute delimiters.
    s = html.escape(text, quote=False)

    # keybind="X" or keybind="X"/  — may end with just `]` or `/]`
    s = re.sub(
        r'\[keybind="([^"]+)"\s*/?\]',
        lambda m: f"<kbd>{html.escape(m.group(1))}</kbd>",
        s,
    )

    # textlink="label" link="id"  (optional trailing /)
    def _textlink(m: re.Match[str]) -> str:
        label = html.escape(m.group("label"))
        link = m.group("link")
        if link in entry_ids:
            return f'<a href="{html.escape(link)}.html">{label}</a>'
        return label

    s = re.sub(
        r'\[textlink="(?P<label>[^"]*)"\s+link="(?P<link>[^"]+)"\s*/?\]',
        _textlink,
        s,
    )

    # [protodata=...] and other self-closing bracket tags — strip quietly
    s = re.sub(
        r"\[protodata=[^\]]*\]",
        '<span class="data">[data]</span>',
        s,
    )

    # Bracket color / bold / italic
    for pat, repl in _INLINE_PATTERNS:
        s = pat.sub(repl, s)

    # Remaining [foo] tags — unknown. Keep them visible for debugging but
    # subdued so they don't scream.
    s = re.sub(
        r"\[([a-zA-Z][^\]]{0,60})\]",
        lambda m: (
            f'<span class="tag-unknown">[{html.escape(m.group(1))}]</span>'
        ),
        s,
    )

    return s


# ---------------------------------------------------------------------------
# Block rendering
# ---------------------------------------------------------------------------


_SELF_CLOSING_XML_TAGS = {
    "GuideEntityEmbed",
    "GuideReagentEmbed",
    "GuideReagentGroupEmbed",
    "GuideLawsetListEmbed",
    "GuideMicrowaveGroupEmbed",
    "GuideTechDisciplineEmbed",
    "CommandButton",
}


def _normalize_xml(raw: str) -> str:
    """Make the guidebook XML actually valid XML.

    - Self-closing-looking tags that lack a trailing `/>` get one.
      Some files have `<GuideEntityEmbed Entity="X"/>` already; others
      have plain open tags. We handle the common pattern.
    - Stray `&` that aren't entities get escaped.
    """
    # Turn `<Foo ... >` (no trailing /) into `<Foo ... />` for known
    # self-closing tag names, when the line doesn't later contain `</Foo>`.
    # Simpler: force `<Foo .../>` for the fixed list.
    for tag in _SELF_CLOSING_XML_TAGS:
        # <Tag ...> not followed by /> — convert to self-closing
        raw = re.sub(
            rf"<{tag}\b([^/>]*)(?<!/)>",
            rf"<{tag}\1/>",
            raw,
        )

    # Escape loose `&` that aren't part of entities
    raw = re.sub(r"&(?![a-zA-Z]+;|#[0-9]+;)", "&amp;", raw)
    return raw


# Module-level sprite cache, set by render_site at build start. Kept
# module-global rather than threaded through every _render_* function to
# avoid touching a dozen signatures for what is effectively a build-wide
# singleton.
_ACTIVE_SPRITE_CACHE: SpriteCache | None = None

# Embed-stats counter (vs-mlg acceptance: ≥80% GuideEntityEmbed → <img>).
# Populated by render_site around each page; reset per build.
_EMBED_STATS = {"entity_total": 0, "entity_img": 0}

# URL prefix for extracted sprite PNGs, relative to the guidebook output
# root. Must match the nginx alias layout — /guidebook/sprites/<id>.png
# is served out of <WEB_ROOT>/sprites/<id>.png with no extra config.
_SPRITE_URL_DIR = "sprites"

# Prototype data indexes populated by render_site, consumed by _render_embed
# for table expansion (vs-3o7). Kept module-global for the same reason the
# sprite cache is: avoids threading 5 extra args through every render fn.
_REAGENTS: dict[str, dict] = {}
_MICROWAVE_RECIPES: dict[str, dict] = {}
_METAMORPH_RECIPES: dict[str, dict] = {}
_DISCIPLINES: dict[str, dict] = {}
_TECHNOLOGIES: dict[str, dict] = {}
_LAWSETS: dict[str, dict] = {}
_LAWS: dict[str, dict] = {}
_LOCALE: dict[str, str] = {}


def _loc(key: str | None, fallback: str | None = None) -> str:
    """Resolve a Fluent locale key to display text, stripping markup.

    Returns `fallback` (or the key itself) when the key is missing so
    tables never render empty cells. Used for reagent/law/tech names.
    """
    if not key:
        return fallback or ""
    val = _LOCALE.get(key)
    if val is None:
        return fallback or key
    return _strip_fluent_markup(val) or (fallback or key)


def _fallback_pill(elem: ET.Element) -> str:
    """Render the original v1 text pill for an embed. Used as a fallback
    when the group/id lookup turns up nothing, so the page never silently
    shows an empty table.
    """
    tag = elem.tag
    attrs = elem.attrib
    label_src = (
        attrs.get("Entity")
        or attrs.get("Reagent")
        or attrs.get("Group")
        or attrs.get("Discipline")
        or attrs.get("Lawset")
        or attrs.get("Caption")
        or tag
    )
    caption = attrs.get("Caption")
    parts = [html.escape(label_src)]
    if caption and caption != label_src:
        parts.append(
            f'<span class="embed-caption">{html.escape(caption)}</span>'
        )
    kind = tag.replace("Guide", "").replace("Embed", "").lower() or "embed"
    return f'<span class="embed embed-{kind}">{" · ".join(parts)}</span>'


# ---------------------------------------------------------------------------
# Reagent effect rendering (vs-05o)
# ---------------------------------------------------------------------------
#
# Effects come from `metabolisms.Bloodstream.effects` and `plantMetabolism`
# on each reagent prototype. In YAML they look like:
#
#     - !type:HealthChange
#       conditions:
#       - !type:ReagentCondition { reagent: Bicaridine, min: 15 }
#       damage:
#         types:
#           Asphyxiation: 0.5
#           Poison: 1.5
#
# `_TagRecordingLoader` preserves the `!type:` under `__type__`. We render
# each effect to a short plain-English sentence, mirroring wiki voice:
# "heals 2 brute damage per unit" not "deals -2 brute per tick".
#
# Unknown types fall back to a literal dump so newly-added effects never
# vanish silently — the guidebook author will see the raw data and file
# a bead to add interpretive rendering.
#
# Nurseshark cross-link: single-reagent detail views get a "Related tools"
# footer linking to https://ss14.zig.computer/nurseshark/reagents/<id>.

_NURSESHARK_REAGENT_URL = "https://ss14.zig.computer/nurseshark/reagents"


def _damage_label(key: str) -> str:
    """Resolve a DamageType / DamageGroup key to its display name.

    Input is the raw SS14 key (`Brute`, `Poison`, `Asphyxiation`, `Heat`).
    We try `damage-type-<lower>` and `damage-group-<lower>` via `_loc`,
    falling back to the key itself (already human-readable).
    """
    if not key:
        return ""
    lower = key.lower()
    type_key = f"damage-type-{lower}"
    if type_key in _LOCALE:
        return _loc(type_key, key)
    group_key = f"damage-group-{lower}"
    if group_key in _LOCALE:
        return _loc(group_key, key)
    return key


def _fmt_num(value: float | int) -> str:
    """Trim trailing zeros: 1.5 → '1.5', 2.0 → '2', -0.5 → '-0.5'."""
    try:
        f = float(value)
    except (TypeError, ValueError):
        return str(value)
    if f == int(f):
        return str(int(f))
    # Two decimals is plenty — SS14 authors rarely use more precision.
    return f"{f:.2f}".rstrip("0").rstrip(".")


def _effect_conditions(effect: dict) -> list[dict]:
    conds = effect.get("conditions") or []
    if not isinstance(conds, list):
        return []
    return [c for c in conds if isinstance(c, dict)]


def _effect_threshold(effect: dict) -> float | None:
    """Return the `ReagentCondition.min` threshold on this effect, or None.

    A `min` of 10 means "applies only when the reagent amount in the body
    is at least 10u." This is how SS14 models overdose: the harm-causing
    effect is gated behind a `ReagentCondition` with a min value.
    """
    for cond in _effect_conditions(effect):
        ctype = cond.get("__type__")
        if ctype != "ReagentCondition":
            continue
        mn = cond.get("min")
        try:
            return float(mn) if mn is not None else None
        except (TypeError, ValueError):
            continue
    return None


def _effect_is_harmful(effect: dict) -> bool:
    """Return True if this effect causes damage or a negative status.

    Used to decide whether a threshold should surface as an OD warning.
    A `HealthChange` with any positive damage value is harmful; `Jitter`,
    `Vomit`, `Drowsiness`, `Stun` etc. are treated as harmful statuses.
    """
    etype = effect.get("__type__") or ""
    if etype in {"HealthChange", "EvenHealthChange"}:
        damage = effect.get("damage") or {}
        if not isinstance(damage, dict):
            return False
        # Any POSITIVE value = damage. Negative = healing, which is OK.
        for nested in ("types", "groups"):
            block = damage.get(nested)
            if isinstance(block, dict):
                for v in block.values():
                    try:
                        if float(v) > 0:
                            return True
                    except (TypeError, ValueError):
                        continue
        # Old-style flat damage dict (no types/groups nesting).
        for k, v in damage.items():
            if k in {"types", "groups"}:
                continue
            try:
                if float(v) > 0:
                    return True
            except (TypeError, ValueError):
                continue
        return False
    harmful = {
        "Vomit",
        "Jitter",
        "Drowsiness",
        "Stun",
        "SlurSpeech",
        "Electrocute",
        "Ignite",
        "Flammable",
        "Polymorph",
        "CauseZombieInfection",
        "ModifyBleed",
    }
    return etype in harmful


def _render_healthchange(effect: dict) -> str:
    """Render HealthChange / EvenHealthChange effects in wiki voice.

    Positive damage = harmful ("deals 1.5 poison per unit"); negative =
    healing ("heals 1.5 brute per unit"). Aggregate across
    damage.types + damage.groups + flat keys.
    """
    damage = effect.get("damage") or {}
    if not isinstance(damage, dict):
        return ""
    entries: list[tuple[str, float]] = []
    for nested in ("types", "groups"):
        block = damage.get(nested)
        if isinstance(block, dict):
            for k, v in block.items():
                try:
                    entries.append((str(k), float(v)))
                except (TypeError, ValueError):
                    continue
    for k, v in damage.items():
        if k in {"types", "groups"}:
            continue
        try:
            entries.append((str(k), float(v)))
        except (TypeError, ValueError):
            continue
    if not entries:
        return "adjusts health"
    heal_parts: list[str] = []
    harm_parts: list[str] = []
    for key, val in entries:
        label = _damage_label(key)
        if val < 0:
            heal_parts.append(f"{_fmt_num(-val)} {label}")
        elif val > 0:
            harm_parts.append(f"{_fmt_num(val)} {label}")
    segments: list[str] = []
    if heal_parts:
        segments.append(f"heals {', '.join(heal_parts)} per unit")
    if harm_parts:
        segments.append(f"deals {', '.join(harm_parts)} damage per unit")
    return "; ".join(segments) if segments else "adjusts health"


def _render_plant_adjust(effect: dict, field_label: str) -> str:
    amt = effect.get("amount")
    try:
        val = float(amt) if amt is not None else 0.0
    except (TypeError, ValueError):
        val = 0.0
    if val > 0:
        return f"raises plant {field_label} by {_fmt_num(val)}"
    if val < 0:
        return f"lowers plant {field_label} by {_fmt_num(-val)}"
    return f"adjusts plant {field_label}"


def _render_effect(effect: dict) -> str:
    """Render a single effect dict as a plain-English sentence.

    Unknown effects fall back to `Type: k=v, k=v` — they're rendered, just
    not interpretively. See the module-level comment for the voice guide.
    """
    etype = effect.get("__type__") or ""

    if etype in {"HealthChange", "EvenHealthChange"}:
        return _render_healthchange(effect)
    if etype == "ModifyBloodLevel":
        amt = effect.get("amount")
        try:
            val = float(amt) if amt is not None else 0.0
        except (TypeError, ValueError):
            val = 0.0
        if val > 0:
            return f"restores blood volume (+{_fmt_num(val)} per tick)"
        if val < 0:
            return f"drains blood volume ({_fmt_num(val)} per tick)"
        return "modifies blood volume"
    if etype == "ModifyBleed":
        amt = effect.get("amount")
        try:
            val = float(amt) if amt is not None else 0.0
        except (TypeError, ValueError):
            val = 0.0
        if val < 0:
            return f"reduces bleeding ({_fmt_num(-val)} per tick)"
        if val > 0:
            return f"worsens bleeding (+{_fmt_num(val)} per tick)"
        return "modifies bleeding"
    if etype == "GenericStatusEffect":
        key = effect.get("key") or effect.get("component") or "status effect"
        time = effect.get("time")
        suffix = f" for {_fmt_num(time)}s" if time is not None else ""
        action = effect.get("type") or "Add"
        if str(action).lower() == "remove":
            return f"removes {key}"
        return f"grants {key}{suffix}"
    if etype == "ModifyStatusEffect":
        proto = effect.get("effectProto") or "status effect"
        time = effect.get("time")
        suffix = f" for {_fmt_num(time)}s" if time is not None else ""
        return f"applies {proto}{suffix}"
    if etype == "Jitter":
        return "causes jittering"
    if etype == "Drowsiness":
        return "causes drowsiness"
    if etype == "Drunk":
        return "causes intoxication"
    if etype == "Stun":
        time = effect.get("time")
        return f"stuns for {_fmt_num(time)}s" if time is not None else "stuns"
    if etype == "ModifyKnockdown":
        return "modifies knockdown"
    if etype == "SlurSpeech":
        return "slurs speech"
    if etype == "Vomit":
        prob = effect.get("probability")
        if prob is not None:
            try:
                pct = float(prob) * 100.0
                return f"induces vomiting ({_fmt_num(pct)}% chance per tick)"
            except (TypeError, ValueError):
                pass
        return "induces vomiting"
    if etype == "Emote":
        emote = effect.get("emote") or "an emote"
        prob = effect.get("probability")
        if prob is not None:
            try:
                pct = float(prob) * 100.0
                return f"triggers emote {emote} ({_fmt_num(pct)}% per tick)"
            except (TypeError, ValueError):
                pass
        return f"triggers emote: {emote}"
    if etype == "PopupMessage":
        return "shows a popup message"
    if etype == "CleanBloodstream":
        excluded = effect.get("excluded")
        rate = effect.get("cleanseRate")
        parts = ["clears other chemicals from the bloodstream"]
        if rate is not None:
            parts.append(f"(rate {_fmt_num(rate)})")
        if excluded:
            parts.append(f"(except {excluded})")
        return " ".join(parts)
    if etype == "AdjustReagent":
        reagent = effect.get("reagent") or "a reagent"
        amt = effect.get("amount")
        if amt is not None:
            try:
                val = float(amt)
                verb = "adds" if val >= 0 else "removes"
                return f"{verb} {_fmt_num(abs(val))}u of {reagent}"
            except (TypeError, ValueError):
                pass
        return f"adjusts {reagent} amount"
    if etype == "AdjustTemperature":
        amt = effect.get("amount")
        if amt is not None:
            try:
                val = float(amt)
                verb = "warms" if val >= 0 else "cools"
                return f"{verb} body ({_fmt_num(val)}°/tick)"
            except (TypeError, ValueError):
                pass
        return "adjusts body temperature"
    if etype == "MovementSpeedModifier":
        walk = effect.get("walkSpeedModifier")
        sprint = effect.get("sprintSpeedModifier")
        parts = []
        if walk is not None:
            parts.append(f"walk x{_fmt_num(walk)}")
        if sprint is not None:
            parts.append(f"sprint x{_fmt_num(sprint)}")
        if parts:
            return "modifies movement (" + ", ".join(parts) + ")"
        return "modifies movement speed"
    if etype == "Oxygenate":
        factor = effect.get("factor")
        if factor is not None:
            try:
                return f"oxygenates blood (factor {_fmt_num(factor)})"
            except (TypeError, ValueError):
                pass
        return "oxygenates blood"
    if etype == "ModifyLungGas":
        return "modifies lung gas composition"
    if etype == "Ignite":
        return "ignites the victim"
    if etype == "Flammable":
        return "makes the victim flammable"
    if etype == "Extinguish":
        return "extinguishes fire"
    if etype == "Electrocute":
        return "electrocutes the victim"
    if etype == "EyeDamage":
        return "damages the eyes"
    if etype == "SatiateHunger":
        factor = effect.get("factor")
        if factor is not None:
            return f"satiates hunger (factor {_fmt_num(factor)})"
        return "satiates hunger"
    if etype == "SatiateThirst":
        factor = effect.get("factor")
        if factor is not None:
            return f"satiates thirst (factor {_fmt_num(factor)})"
        return "satiates thirst"
    if etype == "ReduceRotting":
        return "reduces rotting"
    if etype == "ResetNarcolepsy":
        return "suppresses narcolepsy"
    if etype == "AdjustAlert":
        return "adjusts alert state"
    if etype == "Polymorph":
        proto = effect.get("prototype") or "another entity"
        return f"polymorphs into {proto}"
    if etype == "MakeSentient":
        return "grants sentience"
    if etype == "CauseZombieInfection":
        return "spreads zombie infection"
    if etype == "CureZombieInfection":
        return "cures zombie infection"
    if etype == "ArtifactDurabilityRestore":
        return "restores artifact durability"
    if etype == "ArtifactUnlock":
        return "unlocks an artifact node"

    # Plant-side effects
    if etype == "PlantAdjustHealth":
        return _render_plant_adjust(effect, "health")
    if etype == "PlantAdjustNutrition":
        return _render_plant_adjust(effect, "nutrition")
    if etype == "PlantAdjustWater":
        return _render_plant_adjust(effect, "water")
    if etype == "PlantAdjustToxins":
        return _render_plant_adjust(effect, "toxin level")
    if etype == "PlantAdjustPests":
        amt = effect.get("amount")
        try:
            v = float(amt) if amt is not None else 0.0
        except (TypeError, ValueError):
            v = 0.0
        if v < 0:
            return f"kills pests (strength {_fmt_num(-v)})"
        if v > 0:
            return f"attracts pests ({_fmt_num(v)})"
        return "adjusts plant pests"
    if etype == "PlantAdjustWeeds":
        amt = effect.get("amount")
        try:
            v = float(amt) if amt is not None else 0.0
        except (TypeError, ValueError):
            v = 0.0
        if v < 0:
            return f"kills weeds (strength {_fmt_num(-v)})"
        if v > 0:
            return f"promotes weeds ({_fmt_num(v)})"
        return "adjusts plant weeds"
    if etype == "PlantAdjustPotency":
        return _render_plant_adjust(effect, "potency")
    if etype == "PlantAdjustMutationLevel":
        return _render_plant_adjust(effect, "mutation level")
    if etype == "PlantAdjustMutationMod":
        return _render_plant_adjust(effect, "mutation chance")
    if etype == "PlantAffectGrowth":
        return _render_plant_adjust(effect, "growth")
    if etype == "PlantCryoxadone":
        return "triggers cryoxadone age reversal"
    if etype == "PlantDiethylamine":
        return "applies diethylamine boost"
    if etype == "PlantPhalanximine":
        return "triggers phalanximine mutation"
    if etype == "PlantMutateChemicals":
        return "mutates plant chemical makeup"
    if etype == "PlantRemoveKudzu":
        return "removes kudzu"
    if etype == "PlantRestoreSeeds":
        return "restores lost seeds"
    if etype == "RobustHarvest":
        return "applies Robust Harvest yield boost"

    # Unknown — literal fallback so we never silently drop content.
    if etype:
        extras: list[str] = []
        for k, v in effect.items():
            if k in {"__type__", "conditions"}:
                continue
            extras.append(f"{k}={v}")
        inner = ", ".join(extras) if extras else ""
        return f"{etype}" + (f" ({inner})" if inner else "")
    return "unknown effect"


def _effect_species_notes(effect: dict) -> list[str]:
    """Return any species-specific hints on this effect's conditions.

    E.g. "Only for Vox", "Only in critical state", "Below 50u".
    """
    out: list[str] = []
    for cond in _effect_conditions(effect):
        ctype = cond.get("__type__")
        if ctype == "MetabolizerTypeCondition":
            tset = cond.get("type")
            if isinstance(tset, list):
                labels = ", ".join(str(t) for t in tset)
                out.append(f"only for {labels}")
            elif isinstance(tset, str):
                out.append(f"only for {tset}")
        elif ctype == "MobStateCondition":
            state = cond.get("mobstate")
            if state:
                out.append(f"only when {state}")
        elif ctype == "TemperatureCondition":
            mx = cond.get("max")
            mn = cond.get("min")
            if mx is not None:
                out.append(f"only below {_fmt_num(mx)}K")
            if mn is not None:
                out.append(f"only above {_fmt_num(mn)}K")
        elif ctype == "ReagentCondition":
            mn = cond.get("min")
            mx = cond.get("max")
            if mn is not None:
                out.append(f"above {_fmt_num(mn)}u")
            if mx is not None:
                out.append(f"below {_fmt_num(mx)}u")
        elif ctype == "HungerCondition":
            out.append("only when hungry")
        elif ctype == "BreathingCondition":
            out.append("only while breathing")
        elif ctype == "InternalsCondition":
            out.append("only while on internals")
        elif ctype == "TagCondition":
            tag = cond.get("tag") or cond.get("tags")
            if tag:
                out.append(f"only with tag {tag}")
    return out


def _summarize_effects(effects: list[dict]) -> str:
    """Condensed bullet list of effects for the compact table cell.

    Returns an HTML <ul>. For effects with a `ReagentCondition.min`, the
    threshold is appended inline ("above 15u") so the cell reads as a
    quick glance; the detail view shows the full ladder.
    """
    if not effects:
        return '<span class="effects-none">—</span>'
    items: list[str] = []
    for effect in effects:
        text = _render_effect(effect)
        if not text:
            continue
        notes = _effect_species_notes(effect)
        if notes:
            text = f"{text} ({'; '.join(notes)})"
        items.append(f"<li>{html.escape(text)}</li>")
    if not items:
        return '<span class="effects-none">—</span>'
    return '<ul class="effect-list">' + "".join(items) + "</ul>"


def _max_safe_dose(effects: list[dict]) -> float | None:
    """Return the lowest `ReagentCondition.min` that gates a harmful effect.

    This is the "max safe dose" threshold — the amount of the reagent in
    the body at which damage/status effects kick in. If no harmful effect
    has a threshold, returns None (treated as "Safe" in the column).
    """
    best: float | None = None
    for effect in effects:
        if not _effect_is_harmful(effect):
            continue
        thr = _effect_threshold(effect)
        if thr is None:
            continue
        if best is None or thr < best:
            best = thr
    return best


def _summarize_thresholds(effects: list[dict]) -> str:
    """Compact-column Thresholds cell.

    - "Safe" if no harmful effect has a reagent threshold AND no harmful
      effect is ungated (because an always-on harmful effect is worse
      than any OD).
    - "Toxic" if there's an always-on harmful effect (no threshold).
    - "max safe dose Xu" when a ReagentCondition.min gates harm.
    """
    harmful = [e for e in effects if _effect_is_harmful(e)]
    if not harmful:
        return '<span class="threshold-safe">Safe</span>'
    dose = _max_safe_dose(effects)
    if dose is None:
        # Harm exists but isn't gated — the reagent is toxic from 1u.
        return '<span class="threshold-toxic">Toxic</span>'
    return f'<span class="threshold-od">max safe dose {_fmt_num(dose)}u</span>'


def _threshold_ladder(effects: list[dict]) -> str:
    """Progressive ladder of thresholds for the detail view.

    Groups effects by their ReagentCondition.min and emits a sorted list::

        above 15u: deals 0.5 Asphyxiation per unit, deals 1.5 Poison per unit
        above 30u: induces vomiting (2% per tick)

    Effects with no threshold are listed first under "always active."
    """
    always: list[str] = []
    gated: dict[float, list[str]] = {}
    for effect in effects:
        text = _render_effect(effect)
        if not text:
            continue
        notes = _effect_species_notes(effect)
        # Strip the reagent-min note from species-notes; we surface that
        # as the ladder key to avoid duplicate "above 15u" noise.
        notes = [
            n
            for n in notes
            if not n.startswith("above ") and not n.startswith("below ")
        ]
        if notes:
            text = f"{text} ({'; '.join(notes)})"
        thr = _effect_threshold(effect)
        if thr is None:
            always.append(text)
        else:
            gated.setdefault(thr, []).append(text)
    rows: list[str] = []
    if always:
        rows.append(
            "<li><strong>always active:</strong> "
            + "; ".join(html.escape(t) for t in always)
            + "</li>"
        )
    for thr in sorted(gated.keys()):
        rows.append(
            f"<li><strong>above {_fmt_num(thr)}u:</strong> "
            + "; ".join(html.escape(t) for t in gated[thr])
            + "</li>"
        )
    if not rows:
        return ""
    return '<ul class="threshold-ladder">' + "".join(rows) + "</ul>"


def _group_pill(group: str) -> str:
    """Small colored pill rendering the reagent group (Medicine/Toxin/…)."""
    if not group or group == "Unknown":
        return ""
    slug = re.sub(r"[^a-z0-9]+", "-", group.lower()).strip("-") or "unknown"
    return (
        f'<span class="reagent-group reagent-group-{html.escape(slug)}">'
        f"{html.escape(group)}</span>"
    )


def _reagent_row(rid: str) -> str | None:
    """Compact table row for a reagent id, or None if unknown.

    Columns: Name+swatch, Group pill, Description, Effects bullet list,
    Thresholds cell (max safe dose). Matches the <thead> in
    `_render_reagent_group_embed`.
    """
    r = _REAGENTS.get(rid)
    if r is None:
        return None
    name = _loc(r["name_key"], rid)
    desc = _loc(r["desc_key"], "")
    color = r.get("color")
    swatch = ""
    if isinstance(color, str) and _COLOR_OK.match(color.strip()):
        swatch = (
            f'<span class="reagent-swatch" '
            f'style="background:{html.escape(color.strip())}"></span>'
        )
    group = r.get("group") or ""
    effects = r.get("bloodstream_effects") or []
    plant_effects = r.get("plant_effects") or []
    effects_html = _summarize_effects(effects)
    if plant_effects:
        # Distinct plant section — leaf glyph (literal Unicode, not emoji
        # styling) so narrow terminals still render it.
        effects_html += (
            '<div class="plant-effects"><span class="plant-tag">leaf</span> '
            + _summarize_effects(plant_effects)
            + "</div>"
        )
    thresholds_html = _summarize_thresholds(effects)
    group_html = _group_pill(group)
    return (
        f"<tr>"
        f'<td class="reagent-name">{swatch}{html.escape(name)}</td>'
        f'<td class="reagent-group-cell">{group_html}</td>'
        f'<td class="reagent-desc">{html.escape(desc)}</td>'
        f'<td class="reagent-effects">{effects_html}</td>'
        f'<td class="reagent-thresholds">{thresholds_html}</td>'
        f"</tr>"
    )


def _reagent_detail_view(rid: str) -> str | None:
    """Rich single-reagent layout for `GuideReagentEmbed`.

    Vertical card with:
      - Name + swatch + group pill
      - Description (+ physical desc, flavor if present)
      - Bloodstream effects list
      - Plant metabolism effects list (if any)
      - Threshold ladder
      - Related tools footer (Nurseshark deep-link)
    """
    r = _REAGENTS.get(rid)
    if r is None:
        return None
    name = _loc(r["name_key"], rid)
    desc = _loc(r["desc_key"], "")
    phys = (
        _loc(r.get("physical_desc_key"), "")
        if r.get("physical_desc_key")
        else ""
    )
    flavor = r.get("flavor") or ""
    color = r.get("color")
    swatch = ""
    if isinstance(color, str) and _COLOR_OK.match(color.strip()):
        swatch = (
            f'<span class="reagent-swatch reagent-swatch-big" '
            f'style="background:{html.escape(color.strip())}"></span>'
        )
    group = r.get("group") or ""
    group_html = _group_pill(group)

    effects = r.get("bloodstream_effects") or []
    plant = r.get("plant_effects") or []
    rate = r.get("metabolism_rate")

    sections: list[str] = []

    # Header
    sections.append(
        f'<div class="reagent-card-header">'
        f"{swatch}"
        f'<div class="reagent-card-heading">'
        f'<h3 class="reagent-card-name">{html.escape(name)}</h3>'
        f"{group_html}"
        f"</div></div>"
    )

    # Description + physical desc + flavor
    meta_bits: list[str] = []
    if desc:
        meta_bits.append(f"<p>{html.escape(desc)}</p>")
    subtle: list[str] = []
    if phys:
        subtle.append(f"<em>Appearance:</em> {html.escape(phys)}")
    if flavor:
        subtle.append(f"<em>Flavor:</em> {html.escape(flavor)}")
    if rate is not None:
        subtle.append(f"<em>Metabolism rate:</em> {_fmt_num(rate)} u/s")
    if subtle:
        meta_bits.append(
            '<p class="reagent-subtle">' + " &middot; ".join(subtle) + "</p>"
        )
    if meta_bits:
        sections.append(
            '<div class="reagent-meta">' + "".join(meta_bits) + "</div>"
        )

    # Bloodstream effects
    if effects:
        sections.append(
            '<div class="reagent-section">'
            "<h4>Bloodstream effects</h4>"
            + _summarize_effects(effects)
            + "</div>"
        )

    # Plant effects
    if plant:
        sections.append(
            '<div class="reagent-section plant-effects">'
            '<h4><span class="plant-tag">leaf</span> Plant metabolism</h4>'
            + _summarize_effects(plant)
            + "</div>"
        )

    # Threshold ladder (only useful if there are any thresholds)
    ladder = _threshold_ladder(effects)
    if ladder:
        safe_dose = _max_safe_dose(effects)
        dose_line = ""
        if safe_dose is not None:
            dose_line = (
                f'<p class="reagent-dose">Max safe dose: '
                f"<strong>{_fmt_num(safe_dose)}u</strong></p>"
            )
        sections.append(
            '<div class="reagent-section">'
            "<h4>Thresholds</h4>"
            f"{dose_line}"
            f"{ladder}"
            "</div>"
        )

    # Related tools footer
    sections.append(
        '<div class="reagent-related">'
        '<span class="related-label">Related tools:</span> '
        f'<a href="{_NURSESHARK_REAGENT_URL}/{html.escape(rid)}" '
        'rel="noopener">Nurseshark chem lookup &rarr;</a>'
        "</div>"
    )

    return '<div class="reagent-card">' + "".join(sections) + "</div>"


def _render_reagent_embed(elem: ET.Element) -> str:
    rid = elem.attrib.get("Reagent") or ""
    card = _reagent_detail_view(rid)
    if card is None:
        return _fallback_pill(elem)
    return card


def _render_reagent_group_embed(elem: ET.Element) -> str:
    group = elem.attrib.get("Group") or ""
    matches = [r for r in _REAGENTS.values() if (r.get("group") or "") == group]
    if not matches:
        return _fallback_pill(elem)
    matches.sort(key=lambda r: _loc(r["name_key"], r["id"]).lower())
    rows: list[str] = []
    for r in matches:
        row = _reagent_row(r["id"])
        if row:
            rows.append(row)
    if not rows:
        return _fallback_pill(elem)
    # Responsive wrapper: on narrow widths the CSS collapses the extra
    # columns into a <details>-style expansion per row.
    return (
        '<div class="reagent-group-wrap">'
        '<table class="embed-table reagent-table reagent-group-table">'
        "<thead><tr>"
        "<th>Reagent</th>"
        "<th>Group</th>"
        "<th>Description</th>"
        "<th>Effects</th>"
        "<th>Thresholds</th>"
        "</tr></thead>"
        "<tbody>" + "".join(rows) + "</tbody></table></div>"
    )


def _render_entity_cell(entity_id: str, label: str | None = None) -> str:
    """Inline span with sprite (if resolvable) + label, for recipe cells."""
    cache = _ACTIVE_SPRITE_CACHE
    sprite_name: str | None = None
    if cache is not None:
        try:
            sprite_name = cache.get(entity_id)
        except Exception:
            sprite_name = None
    display = html.escape(label or entity_id)
    if sprite_name:
        src = f"{_SPRITE_URL_DIR}/{html.escape(sprite_name)}"
        return (
            f'<span class="entity-cell">'
            f'<img src="{src}" alt="{html.escape(entity_id)}" '
            f'loading="lazy" width="32" height="32" '
            f'class="entity-cell-img">'
            f'<span class="entity-cell-label">{display}</span>'
            f"</span>"
        )
    return f'<span class="entity-cell">{display}</span>'


def _render_microwave_group_embed(elem: ET.Element) -> str:
    group = elem.attrib.get("Group") or ""
    matches = [
        r
        for r in _MICROWAVE_RECIPES.values()
        if (r.get("group") or "") == group
    ]
    if not matches:
        return _fallback_pill(elem)
    matches.sort(key=lambda r: str(r.get("name") or r["id"]).lower())
    rows: list[str] = []
    for recipe in matches:
        result = recipe.get("result") or ""
        # Recipe name is a plain string in YAML ("bun recipe"); capitalize.
        name_raw = str(recipe.get("name") or recipe["id"])
        name = name_raw[:1].upper() + name_raw[1:]
        result_cell = (
            _render_entity_cell(result, None)
            if result
            else "<em>(no result)</em>"
        )
        input_parts: list[str] = []
        for solid_id, count in (recipe.get("solids") or {}).items():
            input_parts.append(
                f"{_render_entity_cell(str(solid_id), None)} "
                f'<span class="ingredient-count">&times;{html.escape(str(count))}</span>'
            )
        for reagent_id, units in (recipe.get("reagents") or {}).items():
            rname = _loc(
                f"reagent-name-{str(reagent_id).lower()}", str(reagent_id)
            )
            input_parts.append(
                f'<span class="reagent-cell">{html.escape(rname)}</span> '
                f'<span class="ingredient-count">{html.escape(str(units))}u</span>'
            )
        inputs_html = (
            "<br>".join(input_parts) if input_parts else "<em>(no inputs)</em>"
        )
        time_raw = recipe.get("time")
        time_html = (
            f"{html.escape(str(time_raw))}s" if time_raw is not None else ""
        )
        # vs-05o: Appliance column. Today every microwaveMealRecipe is
        # made in a microwave, but the column exists for forward-compat
        # with grill / oven / deep fryer recipe types if SS14 adds them.
        appliance = str(recipe.get("appliance") or "Microwave")
        rows.append(
            f"<tr>"
            f'<td class="recipe-result">{result_cell}</td>'
            f'<td class="recipe-name">{html.escape(name)}</td>'
            f'<td class="recipe-appliance">{html.escape(appliance)}</td>'
            f'<td class="recipe-inputs">{inputs_html}</td>'
            f'<td class="recipe-time">{time_html}</td>'
            f"</tr>"
        )
    return (
        '<table class="embed-table recipe-table">'
        "<thead><tr>"
        "<th>Result</th><th>Recipe</th><th>Appliance</th>"
        "<th>Inputs</th><th>Time</th>"
        "</tr></thead>"
        "<tbody>" + "".join(rows) + "</tbody></table>"
    )


def _render_tech_discipline_embed(elem: ET.Element) -> str:
    disc_id = elem.attrib.get("Discipline") or ""
    disc = _DISCIPLINES.get(disc_id)
    matches = [
        t
        for t in _TECHNOLOGIES.values()
        if (t.get("discipline") or "") == disc_id
    ]
    if not matches:
        return _fallback_pill(elem)
    matches.sort(
        key=lambda t: (
            int(t.get("tier") or 0),
            _loc(t["name_key"], t["id"]).lower(),
        )
    )
    rows: list[str] = []
    for tech in matches:
        name = _loc(tech["name_key"], tech["id"])
        tier = tech.get("tier")
        cost = tech.get("cost")
        rows.append(
            f"<tr>"
            f'<td class="tech-tier">T{html.escape(str(tier or "?"))}</td>'
            f'<td class="tech-name">{html.escape(name)}</td>'
            f'<td class="tech-cost">{html.escape(str(cost or ""))}</td>'
            f"</tr>"
        )
    disc_name = _loc(disc["name_key"], disc_id) if disc is not None else disc_id
    color = disc.get("color") if disc else None
    header_style = ""
    if isinstance(color, str) and _COLOR_OK.match(color.strip()):
        header_style = f' style="color:{html.escape(color.strip())}"'
    return (
        f'<div class="embed-group tech-group">'
        f'<div class="embed-group-title"{header_style}>'
        f"{html.escape(disc_name)}</div>"
        f'<table class="embed-table tech-table">'
        f"<thead><tr>"
        f"<th>Tier</th><th>Technology</th><th>Cost</th>"
        f"</tr></thead>"
        f"<tbody>" + "".join(rows) + "</tbody></table></div>"
    )


def _render_one_lawset(lawset: dict) -> str:
    name = _loc(lawset["name_key"], lawset["id"])
    law_ids = lawset.get("laws") or []
    law_objs = [_LAWS.get(lid) for lid in law_ids if lid in _LAWS]
    law_objs.sort(key=lambda law: int(law.get("order") or 0))  # type: ignore[arg-type]
    items: list[str] = []
    for law in law_objs:
        if law is None:
            continue
        text = _loc(law.get("law_string_key"), "")
        if not text:
            continue
        items.append(f"<li>{html.escape(text)}</li>")
    if not items:
        return ""
    body = '<ol class="lawset-laws">' + "".join(items) + "</ol>"
    return (
        f'<div class="embed-group lawset-group">'
        f'<div class="embed-group-title">{html.escape(name)}</div>'
        f"{body}</div>"
    )


def _render_lawset_list_embed(elem: ET.Element) -> str:
    # In-game the tag currently takes no attributes and lists all lawsets.
    target = elem.attrib.get("Lawset")
    if target:
        lawset = _LAWSETS.get(target)
        if lawset is None:
            return _fallback_pill(elem)
        rendered = _render_one_lawset(lawset)
        return rendered or _fallback_pill(elem)
    if not _LAWSETS:
        return _fallback_pill(elem)
    rendered_all = [
        _render_one_lawset(ls)
        for ls in sorted(
            _LAWSETS.values(),
            key=lambda ls: _loc(ls["name_key"], ls["id"]).lower(),
        )
    ]
    rendered_all = [r for r in rendered_all if r]
    if not rendered_all:
        return _fallback_pill(elem)
    return '<div class="lawset-list">' + "".join(rendered_all) + "</div>"


def _render_embed(elem: ET.Element) -> str:
    """Render an entity/reagent/etc embed.

    Dispatches per tag:

      - `GuideEntityEmbed` → sprite `<img>` (vs-mlg) or text pill fallback
      - `GuideReagentEmbed` → single-row reagent table (vs-3o7)
      - `GuideReagentGroupEmbed` → reagent list table (vs-3o7)
      - `GuideMicrowaveGroupEmbed` → recipe table (vs-3o7)
      - `GuideTechDisciplineEmbed` → technology list table (vs-3o7)
      - `GuideLawsetListEmbed` → ordered lawset + laws (vs-3o7)
      - anything else → text pill (unchanged v1 behavior)

    Every expanded renderer falls back to `_fallback_pill` if its data
    isn't in the index, so unknown reagents / empty groups still render
    visibly rather than silently disappearing.
    """
    tag = elem.tag
    attrs = elem.attrib
    caption = attrs.get("Caption")

    if tag == "GuideReagentEmbed":
        return _render_reagent_embed(elem)
    if tag == "GuideReagentGroupEmbed":
        return _render_reagent_group_embed(elem)
    if tag == "GuideMicrowaveGroupEmbed":
        return _render_microwave_group_embed(elem)
    if tag == "GuideTechDisciplineEmbed":
        return _render_tech_discipline_embed(elem)
    if tag == "GuideLawsetListEmbed":
        return _render_lawset_list_embed(elem)

    label_src = (
        attrs.get("Entity")
        or attrs.get("Reagent")
        or attrs.get("Group")
        or attrs.get("Discipline")
        or attrs.get("Lawset")
        or attrs.get("Caption")
        or tag
    )

    # Sprite path — only for entity embeds with an entity attr.
    if tag == "GuideEntityEmbed" and attrs.get("Entity"):
        _EMBED_STATS["entity_total"] += 1
        entity_id = attrs["Entity"]
        cache = _ACTIVE_SPRITE_CACHE
        sprite_name: str | None = None
        if cache is not None:
            try:
                sprite_name = cache.get(entity_id)
            except Exception as exc:
                print(
                    f"  WARN: sprite resolve failed for {entity_id}: {exc}",
                    file=sys.stderr,
                )
                sprite_name = None
        if sprite_name:
            _EMBED_STATS["entity_img"] += 1
            alt = html.escape(caption or entity_id)
            src = f"{_SPRITE_URL_DIR}/{html.escape(sprite_name)}"
            img = (
                f'<img src="{src}" alt="{alt}" loading="lazy" '
                f'width="64" height="64" class="embed-sprite-img">'
            )
            if caption and caption != entity_id:
                cap_html = (
                    f'<span class="embed-caption">{html.escape(caption)}</span>'
                )
                return (
                    f'<span class="embed embed-entity has-sprite">'
                    f"{img}{cap_html}</span>"
                )
            return f'<span class="embed embed-entity has-sprite">{img}</span>'
        # Resolution failed → fall through to pill below.

    parts = [html.escape(label_src)]
    if caption and caption != label_src:
        parts.append(
            f'<span class="embed-caption">{html.escape(caption)}</span>'
        )
    kind = tag.replace("Guide", "").replace("Embed", "").lower() or "embed"
    return f'<span class="embed embed-{kind}">{" · ".join(parts)}</span>'


def render_body(xml_raw: str, entry_ids: set[str]) -> str:
    """Return the HTML body for one guidebook page."""
    normalized = _normalize_xml(xml_raw)
    try:
        root = ET.fromstring(normalized)
    except ET.ParseError as exc:
        # Some files have stray `<` in text. Fall back to treating the
        # whole thing as inline text between a fake <Document>.
        print(
            f"  WARN: XML parse failed ({exc}); rendering as plain text",
            file=sys.stderr,
        )
        escaped = html.escape(xml_raw)
        return f'<pre class="raw">{escaped}</pre>'

    return _render_children(root, entry_ids)


def _render_children(elem: ET.Element, entry_ids: set[str]) -> str:
    """Walk an element's text + children + tail in document order."""
    out: list[str] = []

    if elem.text:
        out.append(_render_text_block(elem.text, entry_ids))

    for child in elem:
        out.append(_render_element(child, entry_ids))
        if child.tail:
            out.append(_render_text_block(child.tail, entry_ids))

    return "".join(out)


def _render_element(elem: ET.Element, entry_ids: set[str]) -> str:
    tag = elem.tag
    if tag in _SELF_CLOSING_XML_TAGS:
        return _render_embed(elem)
    if tag == "Box":
        return f'<div class="box">{_render_children(elem, entry_ids)}</div>'
    if tag == "ColorBox":
        color = _safe_color(elem.attrib.get("Color", "inherit"))
        return (
            f'<div class="colorbox" style="border-left-color:{color}">'
            f"{_render_children(elem, entry_ids)}</div>"
        )
    if tag == "Table":
        return (
            f'<div class="table-box">{_render_children(elem, entry_ids)}</div>'
        )
    if tag == "Document":
        return _render_children(elem, entry_ids)
    # Unknown container — dump children
    return (
        f'<div class="tag-unknown" data-tag="{html.escape(tag)}">'
        f"{_render_children(elem, entry_ids)}</div>"
    )


def _render_text_block(text: str, entry_ids: set[str]) -> str:
    """Convert a stretch of plain-text (with SS14 bracket syntax) to HTML.

    Line-level rules:
      - `# heading`  → <h2>
      - `## heading` → <h3>
      - `- item`     → bullet
      - blank line   → paragraph break
      - otherwise    → paragraph

    Within each line/paragraph, `render_inline` expands [bold] etc.
    """
    lines = text.split("\n")
    out: list[str] = []
    para_buf: list[str] = []
    list_buf: list[str] = []

    def flush_para() -> None:
        if para_buf:
            joined = " ".join(s.strip() for s in para_buf if s.strip())
            if joined:
                out.append(f"<p>{render_inline(joined, entry_ids)}</p>")
            para_buf.clear()

    def flush_list() -> None:
        if list_buf:
            items = "".join(
                f"<li>{render_inline(i, entry_ids)}</li>" for i in list_buf
            )
            out.append(f"<ul>{items}</ul>")
            list_buf.clear()

    for raw_line in lines:
        line = raw_line.rstrip()
        stripped = line.strip()
        if not stripped:
            flush_para()
            flush_list()
            continue
        if stripped.startswith("## "):
            flush_para()
            flush_list()
            out.append(
                f"<h3>{render_inline(stripped[3:].strip(), entry_ids)}</h3>"
            )
        elif stripped.startswith("# "):
            flush_para()
            flush_list()
            out.append(
                f"<h2>{render_inline(stripped[2:].strip(), entry_ids)}</h2>"
            )
        elif stripped.startswith("- "):
            flush_para()
            list_buf.append(stripped[2:].strip())
        else:
            flush_list()
            para_buf.append(stripped)

    flush_para()
    flush_list()
    return "".join(out)


# ---------------------------------------------------------------------------
# Site assembly
# ---------------------------------------------------------------------------


PAGE_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · VS14 Guidebook</title>
<link rel="stylesheet" href="style.css">
<script>
/* vs-dnz: pre-paint bootstrap. Reads localStorage collapse state and
   applies `open` attrs to <details data-section-id> BEFORE the sidebar
   renders, avoiding a flash where everything looks collapsed then snaps
   back. Also force-opens the active entry's ancestors so users always
   see where they are in the tree. Keep this tiny + dependency-free. */
(function () {{
  var KEY = "vs14-guidebook-nav-state";
  var state = {{}};
  try {{
    var raw = localStorage.getItem(KEY);
    if (raw) state = JSON.parse(raw) || {{}};
  }} catch (e) {{ state = {{}}; }}
  // Walk the ancestor chain for the active entry (server-rendered as
  // ``window.__VS14_ACTIVE_ANCESTORS``) and force those open regardless
  // of stored preference. The array is injected per-page below.
  window.__vs14ApplyNavState = function () {{
    var detailsList = document.querySelectorAll("details[data-section-id]");
    for (var i = 0; i < detailsList.length; i++) {{
      var d = detailsList[i];
      var sid = d.getAttribute("data-section-id");
      if (state[sid] === "open") d.setAttribute("open", "");
    }}
    var anc = window.__VS14_ACTIVE_ANCESTORS || [];
    for (var j = 0; j < anc.length; j++) {{
      var a = document.querySelector(
        'details[data-section-id="' + anc[j] + '"]'
      );
      if (a) a.setAttribute("open", "");
    }}
  }};
  // Defer actual DOM application until the parser has emitted the
  // sidebar — DOMContentLoaded is still pre-paint.
  if (document.readyState === "loading") {{
    document.addEventListener(
      "DOMContentLoaded", window.__vs14ApplyNavState
    );
  }} else {{
    window.__vs14ApplyNavState();
  }}
}})();
</script>
</head>
<body>
<div class="layout">
  <aside class="sidebar">
    <a class="home" href="/">← Vacation Station 14</a>
    <h1><a href="index.html" data-nav-link>Guidebook</a></h1>
    <div class="toc-controls">
      <button type="button" class="toc-ctrl" data-toc-action="expand-all">Expand all</button>
      <button type="button" class="toc-ctrl" data-toc-action="collapse-all">Collapse all</button>
    </div>
    <nav class="toc">{toc}</nav>
  </aside>
  <main id="content" class="content">
    <header class="page-header">
      <nav class="crumbs">{crumbs}</nav>
      <h1>{title}</h1>
    </header>
    <article class="doc">{body}</article>
    <footer class="page-footer">
      <p>Rendered from <code>{source}</code>. Generated by
      <a href="https://github.com/azigler/vacation-station-14">vacation-station-14</a>
      &middot; <a href="/">Back to Vacation Station 14</a></p>
    </footer>
  </main>
</div>
<script>window.__VS14_ACTIVE_ANCESTORS = {ancestors_json};</script>
<script src="guidebook-nav.js" defer></script>
</body>
</html>
"""


INDEX_BODY = """<p>The in-game Guidebook, rendered as a static site for reading outside the client.
Pick a topic on the left to get started, or jump to
<a href="NewPlayer.html">New Player</a> if you've never played before.</p>

<p class="note">Rendering is a minimal subset: text, cross-links, entity
sprites, and tables for reagents / recipes / technologies / lawsets.
Reaction formulas and a handful of niche embeds still fall back to a
label pill — for those, the live game remains the authoritative source.</p>

<h2>Top-level topics</h2>
<ul class="top-level">
{top_list}
</ul>
"""


STYLE_CSS = """:root {
  color-scheme: dark;
  --bg: #0b0f1a;
  --panel: #141b2d;
  --panel-soft: #1a2340;
  --fg: #e8ecf4;
  --dim: #9aa7c0;
  --accent: #6ab0ff;
  --border: #1f2740;
}
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; background: var(--bg); color: var(--fg); }
body {
  font-family: system-ui, -apple-system, sans-serif;
  line-height: 1.55;
  font-size: 16px;
}
a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }
kbd {
  background: #222b45;
  border: 1px solid var(--border);
  border-bottom-width: 2px;
  border-radius: 3px;
  padding: 0.05em 0.4em;
  font-family: ui-monospace, SFMono-Regular, monospace;
  font-size: 0.9em;
  color: #ffe58a;
}
code { font-family: ui-monospace, SFMono-Regular, monospace; }
.layout {
  display: grid;
  grid-template-columns: 18rem 1fr;
  min-height: 100vh;
}
.sidebar {
  background: var(--panel);
  border-right: 1px solid var(--border);
  padding: 1.25rem 1rem;
  overflow-y: auto;
  position: sticky;
  top: 0;
  max-height: 100vh;
}
.sidebar .home { display: block; color: var(--dim); font-size: 0.85rem; margin-bottom: 0.75rem; }
.sidebar h1 { font-size: 1.15rem; margin: 0 0 1rem; letter-spacing: -0.01em; }
.sidebar h1 a { color: var(--fg); }
.toc ul { list-style: none; padding-left: 1rem; margin: 0.25rem 0; }
.toc > ul { padding-left: 0; }
.toc li { margin: 0.15rem 0; }
.toc a {
  display: block;
  padding: 0.15rem 0.35rem;
  border-radius: 4px;
  color: var(--fg);
  font-size: 0.92rem;
}
.toc a:hover { background: var(--panel-soft); text-decoration: none; }
.toc a.current { background: var(--panel-soft); color: var(--accent); }

/* vs-dnz: collapsible sidebar sections (<details> per parent) + nav controls */
.toc details { margin: 0; }
.toc details > summary {
  list-style: none;
  display: flex;
  align-items: center;
  gap: 0.15rem;
  cursor: default;
}
.toc details > summary::-webkit-details-marker { display: none; }
.toc details > summary::marker { content: ""; }
.toc .toc-toggle {
  flex: 0 0 auto;
  width: 1.1rem;
  height: 1.1rem;
  padding: 0;
  margin: 0;
  background: transparent;
  border: 0;
  color: var(--dim);
  cursor: pointer;
  font-size: 0.8rem;
  line-height: 1;
  border-radius: 3px;
  transition: transform 150ms ease, color 120ms ease;
}
.toc .toc-toggle::before { content: "\\25B8"; /* ▸ */ }
.toc details[open] > summary > .toc-toggle { transform: rotate(90deg); }
.toc details[open] > summary > .toc-toggle::before { color: var(--accent); }
.toc .toc-toggle:hover { color: var(--accent); background: var(--panel-soft); }
.toc details > summary > a { flex: 1 1 auto; min-width: 0; }
.toc details > ul {
  overflow: hidden;
  max-height: 0;
  opacity: 0;
  transition: max-height 150ms ease, opacity 150ms ease;
}
.toc details[open] > ul {
  max-height: none;
  opacity: 1;
}
@media (prefers-reduced-motion: reduce) {
  .toc details > ul { transition: none; }
  .toc .toc-toggle { transition: none; }
}
.toc-controls {
  display: flex;
  gap: 0.4rem;
  margin-bottom: 0.65rem;
}
.toc-controls .toc-ctrl {
  flex: 1;
  background: var(--panel-soft);
  color: var(--dim);
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: 0.25rem 0.4rem;
  font-size: 0.78rem;
  cursor: pointer;
  font-family: inherit;
  transition: color 120ms ease, border-color 120ms ease;
}
.toc-controls .toc-ctrl:hover {
  color: var(--accent);
  border-color: var(--accent);
}
/* Content swap: a subtle opacity pulse signals the partial nav exchange
   without a full flicker. Driven by the `.is-loading` class set by
   guidebook-nav.js around the fetch. */
.content { transition: opacity 120ms ease; }
.content.is-loading { opacity: 0.4; }
.content { padding: 2rem clamp(1rem, 3vw, 2.5rem); max-width: 64rem; }
.page-header h1 {
  font-size: clamp(1.75rem, 3vw, 2.25rem);
  margin: 0.25rem 0 1.5rem;
  letter-spacing: -0.02em;
}
.crumbs { color: var(--dim); font-size: 0.9rem; }
.crumbs a { color: var(--dim); }
.crumbs a:hover { color: var(--accent); }
.doc h2 { font-size: 1.4rem; margin: 1.75rem 0 0.5rem; border-bottom: 1px solid var(--border); padding-bottom: 0.25rem; }
.doc h3 { font-size: 1.15rem; margin: 1.25rem 0 0.4rem; color: var(--accent); }
.doc p { margin: 0.5rem 0; }
.doc ul { padding-left: 1.5rem; }
.doc li { margin: 0.2rem 0; }
.doc .box {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  background: var(--panel);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 0.75rem 1rem;
  margin: 1rem 0;
}
.doc .colorbox {
  background: var(--panel);
  border-left: 4px solid var(--accent);
  border-radius: 4px;
  padding: 0.5rem 1rem;
  margin: 0.75rem 0;
}
.doc .table-box {
  background: var(--panel);
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: 0.5rem 1rem;
  margin: 0.75rem 0;
}
.embed {
  display: inline-block;
  background: var(--panel-soft);
  border: 1px solid var(--border);
  border-radius: 999px;
  padding: 0.1rem 0.6rem;
  font-size: 0.85rem;
  font-family: ui-monospace, SFMono-Regular, monospace;
  color: var(--dim);
}
.embed-caption { color: var(--fg); margin-left: 0.25rem; }
.embed.has-sprite {
  background: var(--panel);
  border-radius: 6px;
  padding: 0.25rem 0.5rem;
  vertical-align: middle;
}
.embed-sprite-img {
  width: 64px;
  height: 64px;
  image-rendering: pixelated;
  image-rendering: crisp-edges;
  vertical-align: middle;
  display: inline-block;
}
.tag-unknown {
  color: #d07a7a;
  font-family: ui-monospace, SFMono-Regular, monospace;
  font-size: 0.85em;
}
.data { color: var(--dim); font-family: ui-monospace, SFMono-Regular, monospace; font-size: 0.85em; }
pre.raw { white-space: pre-wrap; background: var(--panel); padding: 1rem; border-radius: 4px; color: var(--dim); font-size: 0.85em; }
.page-footer { margin-top: 3rem; padding-top: 1rem; border-top: 1px solid var(--border); color: var(--dim); font-size: 0.85rem; }
.note { color: var(--dim); font-size: 0.9rem; border-left: 3px solid var(--border); padding-left: 0.75rem; }
.top-level { list-style: none; padding: 0; }
.top-level li { margin: 0.5rem 0; }
.top-level a { font-size: 1.05rem; font-weight: 600; }
@media (max-width: 800px) {
  .layout { grid-template-columns: 1fr; }
  .sidebar { position: static; max-height: none; }
}

/* vs-3o7: expanded embed tables (reagents / recipes / tech / lawsets) */
.embed-table {
  width: 100%;
  border-collapse: collapse;
  margin: 0.75rem 0 1.25rem;
  background: var(--panel);
  border: 1px solid var(--border);
  border-radius: 6px;
  overflow: hidden;
  font-size: 0.92rem;
}
.embed-table thead th {
  background: var(--panel-soft);
  color: var(--dim);
  text-align: left;
  padding: 0.5rem 0.75rem;
  font-size: 0.85rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  border-bottom: 1px solid var(--border);
}
.embed-table tbody td {
  padding: 0.5rem 0.75rem;
  border-top: 1px solid var(--border);
  vertical-align: top;
}
.embed-table tbody tr:first-child td { border-top: none; }
.embed-table tbody tr:nth-child(even) { background: rgba(255, 255, 255, 0.015); }
.reagent-table .reagent-name {
  white-space: nowrap;
  font-weight: 600;
  color: var(--fg);
}
.reagent-table .reagent-desc { color: var(--dim); }
.reagent-swatch {
  display: inline-block;
  width: 0.8em;
  height: 0.8em;
  border-radius: 2px;
  border: 1px solid var(--border);
  margin-right: 0.4em;
  vertical-align: middle;
}
.recipe-table .recipe-result,
.recipe-table .recipe-name {
  white-space: nowrap;
}
.recipe-table .recipe-time {
  color: var(--dim);
  white-space: nowrap;
  font-family: ui-monospace, SFMono-Regular, monospace;
  font-size: 0.85em;
}
.entity-cell {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
}
.entity-cell-img {
  width: 32px;
  height: 32px;
  image-rendering: pixelated;
  image-rendering: crisp-edges;
}
.entity-cell-label { font-size: 0.9em; }
.ingredient-count {
  color: var(--dim);
  font-family: ui-monospace, SFMono-Regular, monospace;
  font-size: 0.85em;
}
.reagent-cell { color: var(--fg); }
.tech-table .tech-tier {
  width: 3rem;
  font-family: ui-monospace, SFMono-Regular, monospace;
  color: var(--accent);
  font-weight: 600;
}
.tech-table .tech-cost {
  color: var(--dim);
  font-family: ui-monospace, SFMono-Regular, monospace;
  text-align: right;
  width: 6rem;
}
.embed-group {
  margin: 1rem 0 1.5rem;
  background: var(--panel);
  border: 1px solid var(--border);
  border-radius: 6px;
  overflow: hidden;
}
.embed-group > .embed-table {
  margin: 0;
  border: none;
  border-radius: 0;
}
.embed-group-title {
  padding: 0.5rem 0.85rem;
  font-weight: 600;
  background: var(--panel-soft);
  border-bottom: 1px solid var(--border);
}
.lawset-list { display: flex; flex-direction: column; gap: 0.5rem; }
.lawset-group .lawset-laws {
  margin: 0;
  padding: 0.75rem 1rem 0.75rem 2.25rem;
  color: var(--fg);
}
.lawset-group .lawset-laws li { margin: 0.25rem 0; }

/* vs-05o: richer reagent tables (effects + thresholds + group pills) */
.reagent-group { /* small group pill inside reagent-group-cell */
  display: inline-block;
  font-size: 0.72rem;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  padding: 0.08rem 0.45rem;
  border-radius: 999px;
  background: var(--panel-soft);
  border: 1px solid var(--border);
  color: var(--dim);
  white-space: nowrap;
}
.reagent-group-medicine { color: #6ab0ff; border-color: #2a4466; }
.reagent-group-toxin { color: #e08b6a; border-color: #663a2a; }
.reagent-group-narcotic { color: #c98bf0; border-color: #4d2a66; }
.reagent-group-biological { color: #8be38b; border-color: #2a663a; }
.reagent-group-drink { color: #ffd27a; border-color: #66552a; }
.reagent-group-food { color: #f0c97a; border-color: #665a2a; }
.reagent-group-botanical { color: #8be38b; border-color: #2a663a; }
.reagent-group-pyrotechnic { color: #ff7a7a; border-color: #662a2a; }
.reagent-group-admin { color: #d07a7a; border-color: #663a3a; }
.reagent-effects .effect-list {
  margin: 0;
  padding-left: 1.05rem;
  color: var(--fg);
  font-size: 0.86rem;
  line-height: 1.35;
}
.reagent-effects .effect-list li { margin: 0.1rem 0; }
.reagent-effects .effects-none { color: var(--dim); font-style: italic; }
.reagent-thresholds {
  white-space: nowrap;
  font-size: 0.85rem;
}
.threshold-safe { color: #8be38b; }
.threshold-od { color: #ffd27a; }
.threshold-toxic { color: #ff7a7a; font-weight: 600; }
.plant-effects {
  margin-top: 0.35rem;
  padding-top: 0.35rem;
  border-top: 1px dashed var(--border);
}
.plant-effects .plant-tag {
  display: inline-block;
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  padding: 0.05rem 0.35rem;
  margin-right: 0.3rem;
  background: rgba(139, 227, 139, 0.12);
  color: #8be38b;
  border: 1px solid #2a663a;
  border-radius: 4px;
  vertical-align: baseline;
}

/* Rich single-reagent detail card (GuideReagentEmbed) */
.reagent-card {
  background: var(--panel);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 1rem 1.15rem;
  margin: 0.75rem 0 1.25rem;
}
.reagent-card-header {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  margin-bottom: 0.5rem;
}
.reagent-card-heading {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  flex-wrap: wrap;
}
.reagent-card-name {
  margin: 0;
  font-size: 1.15rem;
  color: var(--fg);
}
.reagent-swatch-big {
  width: 1.35em;
  height: 1.35em;
  border-radius: 4px;
  margin-right: 0;
}
.reagent-meta p { margin: 0.3rem 0; }
.reagent-subtle { color: var(--dim); font-size: 0.88rem; }
.reagent-section { margin-top: 0.85rem; }
.reagent-section h4 {
  margin: 0 0 0.3rem;
  font-size: 0.92rem;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--dim);
}
.reagent-section .effect-list {
  margin: 0;
  padding-left: 1.15rem;
  color: var(--fg);
  font-size: 0.93rem;
  line-height: 1.4;
}
.reagent-section.plant-effects {
  padding-top: 0.85rem;
  border-top: 1px dashed var(--border);
  margin-top: 0.85rem;
}
.reagent-dose { margin: 0.2rem 0 0.4rem; color: var(--fg); }
.threshold-ladder {
  margin: 0.3rem 0 0;
  padding-left: 1.25rem;
  font-size: 0.92rem;
  color: var(--fg);
}
.threshold-ladder li { margin: 0.2rem 0; }
.reagent-related {
  margin-top: 1rem;
  padding-top: 0.6rem;
  border-top: 1px solid var(--border);
  font-size: 0.85rem;
  color: var(--dim);
}
.reagent-related .related-label { margin-right: 0.35rem; }

/* Recipe table appliance column */
.recipe-table .recipe-appliance {
  color: var(--dim);
  font-size: 0.85em;
  white-space: nowrap;
  font-family: ui-monospace, SFMono-Regular, monospace;
}

/* Responsive: collapse reagent-group-table extra columns on narrow widths */
@media (max-width: 720px) {
  .reagent-group-table thead th:nth-child(3),
  .reagent-group-table thead th:nth-child(4),
  .reagent-group-table tbody td:nth-child(3),
  .reagent-group-table tbody td:nth-child(4) {
    display: none;
  }
  .reagent-group-table .reagent-thresholds {
    font-size: 0.78rem;
  }
  .recipe-table thead th:nth-child(3),
  .recipe-table tbody td:nth-child(3) {
    display: none;
  }
}
"""


# vs-dnz: client-side sidebar state + partial-content navigation.
# Plain ES5-ish JS so it runs without a build step and on every modern
# browser the guidebook targets. Progressive enhancement only: if this
# file fails to load or the browser has JS disabled, the sidebar still
# works (every entry has a real ``href``) and the content pane still
# renders fine (the sidebar simply shows everything expanded by default
# via a :has fallback? No — we default to closed via <details> without
# `open`, matching the JS-on default. Walking ancestors of the current
# page is the bootstrap's job; see PAGE_TEMPLATE inline script).
GUIDEBOOK_NAV_JS = """/* vs-dnz: guidebook sidebar + partial-nav enhancement */
(function () {
  "use strict";

  var STATE_KEY = "vs14-guidebook-nav-state";
  var NAV_ROOT = document.querySelector(".sidebar .toc");
  var CONTENT = document.getElementById("content");

  function readState() {
    try {
      var raw = localStorage.getItem(STATE_KEY);
      return raw ? JSON.parse(raw) || {} : {};
    } catch (_) { return {}; }
  }

  function writeState(state) {
    try { localStorage.setItem(STATE_KEY, JSON.stringify(state)); }
    catch (_) { /* quota / privacy mode — silently ignore */ }
  }

  /* ---- Part 1: collapse/expand state persistence ------------------ */

  function wireDetailsToggle() {
    var nodes = document.querySelectorAll("details[data-section-id]");
    for (var i = 0; i < nodes.length; i++) {
      nodes[i].addEventListener("toggle", onToggle);
    }
  }

  function onToggle(ev) {
    var d = ev.currentTarget;
    var sid = d.getAttribute("data-section-id");
    if (!sid) return;
    var state = readState();
    if (d.open) state[sid] = "open"; else delete state[sid];
    writeState(state);
  }

  function wireTocToggleButtons() {
    /* Chevron button: toggle the parent <details> open state. We
       listen on the root (event delegation) so re-running this after
       a content swap is cheap. */
    if (!NAV_ROOT) return;
    NAV_ROOT.addEventListener("click", function (ev) {
      var btn = ev.target && ev.target.closest
        ? ev.target.closest(".toc-toggle") : null;
      if (!btn) return;
      var d = btn.closest("details[data-section-id]");
      if (!d) return;
      ev.preventDefault();
      ev.stopPropagation();
      d.open = !d.open;
    });
  }

  function wireCollapseAll() {
    var buttons = document.querySelectorAll(".toc-controls [data-toc-action]");
    for (var i = 0; i < buttons.length; i++) {
      buttons[i].addEventListener("click", onCollapseAllClick);
    }
  }

  function onCollapseAllClick(ev) {
    var action = ev.currentTarget.getAttribute("data-toc-action");
    var nodes = document.querySelectorAll("details[data-section-id]");
    var state = readState();
    for (var i = 0; i < nodes.length; i++) {
      var d = nodes[i];
      var sid = d.getAttribute("data-section-id");
      if (action === "expand-all") {
        d.open = true;
        if (sid) state[sid] = "open";
      } else if (action === "collapse-all") {
        d.open = false;
        if (sid) delete state[sid];
      }
    }
    writeState(state);
  }

  /* ---- Part 2: partial-content navigation ------------------------- */

  function isSameOrigin(href) {
    try {
      var u = new URL(href, window.location.href);
      return u.origin === window.location.origin;
    } catch (_) { return false; }
  }

  function hardNav(href) { window.location.href = href; }

  function parseFragment(htmlText) {
    var doc;
    try {
      doc = new DOMParser().parseFromString(htmlText, "text/html");
    } catch (_) { return null; }
    var newContent = doc.getElementById("content");
    var newTitle = doc.querySelector("title");
    return {
      content: newContent,
      title: newTitle ? newTitle.textContent : null,
    };
  }

  function fetchAndSwap(href, pushHistory) {
    if (!CONTENT) { hardNav(href); return; }
    CONTENT.classList.add("is-loading");
    fetch(href, { credentials: "same-origin" })
      .then(function (resp) {
        if (!resp.ok) throw new Error("HTTP " + resp.status);
        return resp.text();
      })
      .then(function (text) {
        var parsed = parseFragment(text);
        if (!parsed || !parsed.content) {
          hardNav(href);
          return;
        }
        CONTENT.innerHTML = parsed.content.innerHTML;
        if (parsed.title) document.title = parsed.title;
        if (pushHistory) history.pushState({}, "", href);
        updateActiveLink(href);
        CONTENT.classList.remove("is-loading");
        if (CONTENT.scrollTo) CONTENT.scrollTo(0, 0);
        window.scrollTo(0, 0);
        window.dispatchEvent(new CustomEvent("nav:loaded", {
          detail: { href: href }
        }));
      })
      .catch(function () {
        CONTENT.classList.remove("is-loading");
        hardNav(href);
      });
  }

  function updateActiveLink(href) {
    var path = href.split("#")[0].split("?")[0];
    var filename = path.split("/").pop();
    var links = document.querySelectorAll("a[data-nav-link]");
    for (var i = 0; i < links.length; i++) {
      var a = links[i];
      var linkHref = a.getAttribute("href");
      var isMatch = linkHref === filename;
      if (isMatch) {
        a.classList.add("current");
        a.setAttribute("aria-current", "page");
      } else {
        a.classList.remove("current");
        a.removeAttribute("aria-current");
      }
    }
  }

  function onNavClick(ev) {
    if (ev.defaultPrevented) return;
    if (ev.button && ev.button !== 0) return;
    if (ev.metaKey || ev.ctrlKey || ev.shiftKey || ev.altKey) return;
    var a = ev.target && ev.target.closest
      ? ev.target.closest("a[data-nav-link]") : null;
    if (!a) return;
    var href = a.getAttribute("href");
    if (!href || href.charAt(0) === "#") return;
    if (!isSameOrigin(href)) return;
    if (a.target && a.target !== "" && a.target !== "_self") return;
    ev.preventDefault();
    fetchAndSwap(href, true);
  }

  function onPopState() {
    fetchAndSwap(window.location.href, false);
  }

  function wireNav() {
    document.addEventListener("click", onNavClick);
    window.addEventListener("popstate", onPopState);
  }

  /* ---- Boot ------------------------------------------------------- */

  function boot() {
    /* The inline <head> bootstrap already restored localStorage state +
       force-opened active-ancestor sections before paint; here we only
       wire event listeners. */
    wireDetailsToggle();
    wireTocToggleButtons();
    wireCollapseAll();
    wireNav();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
"""


def resolve_label(entry: dict, labels: dict[str, str]) -> str:
    key = entry.get("name_key") or ""
    if key in labels:
        return labels[key]
    return entry["id"]


def build_roots(entries: dict[str, dict]) -> list[str]:
    """Top-level entries, sorted by (priority, label)."""
    roots = [eid for eid, e in entries.items() if e["parent"] is None]
    roots.sort(key=lambda eid: (entries[eid]["priority"], eid))
    return roots


def _entry_ancestors(eid: str | None, entries: dict[str, dict]) -> list[str]:
    """vs-dnz: walk parents of ``eid`` so the inline bootstrap can force
    the active entry's ``<details>`` ancestors open pre-paint. Excludes
    ``eid`` itself (its own `<details>` wrapper, if any, is not forced
    open — only the chain above it)."""
    if not eid or eid not in entries:
        return []
    chain: list[str] = []
    cur = entries[eid].get("parent")
    guard = 0
    while cur and cur in entries and guard < 64:
        chain.append(cur)
        cur = entries[cur].get("parent")
        guard += 1
    return chain


def build_toc(
    entries: dict[str, dict], labels: dict[str, str], current: str | None
) -> str:
    """Render the sidebar TOC tree.

    vs-dnz: Entries that have children are wrapped in a ``<details>``
    element with a stable ``data-section-id`` so client-side JS can
    persist their open/closed state in ``localStorage``. Every link
    also gets ``data-nav-link`` so the partial-navigation JS can
    intercept clicks (``<a>`` still carries a real ``href`` for the
    no-JS fallback). The currently-active entry is marked with
    ``aria-current="page"``; an inline ``<head>`` bootstrap script
    reopens its ``<details>`` ancestors before first paint.
    """
    roots = build_roots(entries)
    visited: set[str] = set()

    def render_node(eid: str) -> str:
        if eid in visited or eid not in entries:
            return ""
        visited.add(eid)
        e = entries[eid]
        label = html.escape(resolve_label(e, labels))
        sid = html.escape(eid)
        link_attrs = [
            f'href="{sid}.html"',
            "data-nav-link",
            f'data-entry-id="{sid}"',
        ]
        if eid == current:
            link_attrs.append('class="current"')
            link_attrs.append('aria-current="page"')
        link = f"<a {' '.join(link_attrs)}>{label}</a>"

        child_eids = [c for c in e["children"] if c in entries]
        if not child_eids:
            return f"<li>{link}</li>"

        parts = [render_node(c) for c in child_eids]
        parts = [p for p in parts if p]
        if not parts:
            return f"<li>{link}</li>"

        children_html = "<ul>" + "".join(parts) + "</ul>"
        # Parent: wrap the link + children UL in a <details> so the
        # whole subtree collapses. The <summary> holds the link so
        # clicking the text navigates; a separate chevron button
        # controls open/close without triggering navigation.
        return (
            f'<li class="toc-parent">'
            f'<details data-section-id="{sid}">'
            f"<summary>"
            f'<button class="toc-toggle" type="button" aria-label="Toggle section" tabindex="-1"></button>'
            f"{link}"
            f"</summary>"
            f"{children_html}"
            f"</details>"
            f"</li>"
        )

    items = "".join(render_node(r) for r in roots)
    return f"<ul>{items}</ul>"


def build_crumbs(
    entry: dict, entries: dict[str, dict], labels: dict[str, str]
) -> str:
    chain: list[dict] = []
    cur: dict | None = entry
    guard = 0
    while cur is not None and guard < 64:
        chain.append(cur)
        parent = cur.get("parent")
        cur = entries.get(parent) if parent else None
        guard += 1
    chain.reverse()
    parts = ['<a href="index.html">Guidebook</a>']
    for e in chain[:-1]:
        parts.append(
            f'<a href="{e["id"]}.html">{html.escape(resolve_label(e, labels))}</a>'
        )
    parts.append(html.escape(resolve_label(chain[-1], labels)))
    return " &rsaquo; ".join(parts)


def _resolve_xml_path(repo: Path, text_path: str) -> Path | None:
    """SS14 text paths are like `/ServerInfo/Guidebook/Foo.xml`."""
    if not text_path:
        return None
    rel = text_path.lstrip("/")
    candidate = repo / "Resources" / rel
    if candidate.exists():
        return candidate
    return None


def render_site(repo: Path, out: Path) -> int:
    global _ACTIVE_SPRITE_CACHE
    global _REAGENTS, _MICROWAVE_RECIPES, _METAMORPH_RECIPES
    global _DISCIPLINES, _TECHNOLOGIES
    global _LAWSETS, _LAWS, _LOCALE
    entries = load_entries(repo)
    labels = load_labels(repo)
    entry_ids = set(entries)

    out.mkdir(parents=True, exist_ok=True)
    (out / "style.css").write_text(STYLE_CSS, encoding="utf-8")
    # vs-dnz: sidebar state persistence + partial-nav enhancement.
    # Referenced from PAGE_TEMPLATE as `<script src="guidebook-nav.js" defer>`.
    (out / "guidebook-nav.js").write_text(GUIDEBOOK_NAV_JS, encoding="utf-8")

    # vs-3o7: prototype + locale indexes for embed table expansion. Each
    # scan is soft-failed — a broken reagent yml should not tank the
    # whole guidebook build; the embed just falls back to a pill.
    try:
        _LOCALE = load_all_locale(repo)
        print(f"  indexed {len(_LOCALE)} locale message(s)", file=sys.stderr)
    except Exception as exc:
        print(f"  WARN: locale scan failed ({exc})", file=sys.stderr)
        _LOCALE = {}
    try:
        _REAGENTS = load_reagents(repo)
        print(f"  indexed {len(_REAGENTS)} reagent(s)", file=sys.stderr)
    except Exception as exc:
        print(f"  WARN: reagent scan failed ({exc})", file=sys.stderr)
        _REAGENTS = {}
    try:
        _MICROWAVE_RECIPES = load_microwave_recipes(repo)
        print(
            f"  indexed {len(_MICROWAVE_RECIPES)} microwave recipe(s)",
            file=sys.stderr,
        )
    except Exception as exc:
        print(f"  WARN: recipe scan failed ({exc})", file=sys.stderr)
        _MICROWAVE_RECIPES = {}
    try:
        # vs-05o: metamorph recipes are indexed but not yet rendered
        # (no in-game embed surfaces them; see docs/guidebook-parity.md).
        _METAMORPH_RECIPES = load_metamorph_recipes(repo)
        print(
            f"  indexed {len(_METAMORPH_RECIPES)} metamorph recipe(s)",
            file=sys.stderr,
        )
    except Exception as exc:
        print(f"  WARN: metamorph scan failed ({exc})", file=sys.stderr)
        _METAMORPH_RECIPES = {}
    try:
        _DISCIPLINES, _TECHNOLOGIES = load_research(repo)
        print(
            f"  indexed {len(_DISCIPLINES)} discipline(s), "
            f"{len(_TECHNOLOGIES)} technology(ies)",
            file=sys.stderr,
        )
    except Exception as exc:
        print(f"  WARN: research scan failed ({exc})", file=sys.stderr)
        _DISCIPLINES, _TECHNOLOGIES = {}, {}
    try:
        _LAWSETS, _LAWS = load_lawsets(repo)
        print(
            f"  indexed {len(_LAWSETS)} lawset(s), {len(_LAWS)} law(s)",
            file=sys.stderr,
        )
    except Exception as exc:
        print(f"  WARN: lawset scan failed ({exc})", file=sys.stderr)
        _LAWSETS, _LAWS = {}, {}

    # Build the entity→sprite index. Soft-fail (log + disable sprites)
    # if the prototype scan blows up — the guidebook should still ship
    # with text-pill embeds in that case.
    sprite_cache: SpriteCache | None = None
    try:
        print("scanning entity prototypes for sprite data...", file=sys.stderr)
        entity_sprites = load_entity_sprites(repo)
        print(
            f"  indexed {len(entity_sprites)} entity prototype(s)",
            file=sys.stderr,
        )
        sprite_cache = SpriteCache(
            repo=repo,
            out_dir=out / _SPRITE_URL_DIR,
            entities=entity_sprites,
        )
    except Exception as exc:
        print(
            f"  WARN: entity sprite index failed ({exc}); "
            f"falling back to text pills",
            file=sys.stderr,
        )
        sprite_cache = None
    _ACTIVE_SPRITE_CACHE = sprite_cache
    _EMBED_STATS["entity_total"] = 0
    _EMBED_STATS["entity_img"] = 0

    rendered = 0
    skipped = 0

    for eid, entry in entries.items():
        xml_path = _resolve_xml_path(repo, entry["text"])
        if xml_path is None:
            # Some entries are category headers with no standalone XML.
            # Still render a landing page for them that lists children.
            body = _stub_body(entry, entries, labels)
        else:
            xml_raw = xml_path.read_text(encoding="utf-8")
            try:
                body = render_body(xml_raw, entry_ids)
            except Exception as exc:
                print(f"  WARN: {eid}: render failed ({exc})", file=sys.stderr)
                body = (
                    f"<p><em>(Render error: {html.escape(str(exc))})</em></p>"
                )
                skipped += 1

        title = resolve_label(entry, labels)
        toc = build_toc(entries, labels, eid)
        crumbs = build_crumbs(entry, entries, labels)
        source = html.escape(entry.get("text") or "(no source)")
        ancestors = _entry_ancestors(eid, entries)
        page = PAGE_TEMPLATE.format(
            title=html.escape(title),
            toc=toc,
            crumbs=crumbs,
            body=body,
            source=source,
            ancestors_json=json.dumps(ancestors),
        )
        (out / f"{eid}.html").write_text(page, encoding="utf-8")
        rendered += 1

    # Index page
    roots = build_roots(entries)
    top_items = "".join(
        f'<li><a href="{r}.html">{html.escape(resolve_label(entries[r], labels))}</a></li>'
        for r in roots
    )
    index_body = INDEX_BODY.format(top_list=top_items)
    index_page = PAGE_TEMPLATE.format(
        title="Guidebook",
        toc=build_toc(entries, labels, None),
        crumbs='<a href="index.html">Guidebook</a>',
        body=index_body,
        source="(index)",
        ancestors_json=json.dumps([]),
    )
    (out / "index.html").write_text(index_page, encoding="utf-8")

    print(
        f"rendered {rendered} page(s), {skipped} with fallback, wrote index.html"
    )
    total = _EMBED_STATS["entity_total"]
    imgs = _EMBED_STATS["entity_img"]
    if total:
        pct = 100.0 * imgs / total
        print(
            f"GuideEntityEmbed: {imgs}/{total} rendered as <img> ({pct:.1f}%), "
            f"{total - imgs} fell back to text pill"
        )
    _ACTIVE_SPRITE_CACHE = None
    return 0


def _stub_body(
    entry: dict, entries: dict[str, dict], labels: dict[str, str]
) -> str:
    """Fallback body for entries that declare no XML `text` source."""
    kids = entry.get("children") or []
    if not kids:
        return "<p><em>No content for this entry.</em></p>"
    items = "".join(
        f'<li><a href="{k}.html">{html.escape(resolve_label(entries[k], labels))}</a></li>'
        for k in kids
        if k in entries
    )
    return f"<p>This topic groups the following pages:</p><ul>{items}</ul>"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo", required=True, type=Path, help="VS14 repo root")
    ap.add_argument("--out", required=True, type=Path, help="output dir")
    args = ap.parse_args(argv)

    if not (args.repo / "Resources").is_dir():
        print(
            f"ERROR: {args.repo} does not look like a VS14 checkout",
            file=sys.stderr,
        )
        return 2

    return render_site(args.repo, args.out)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
