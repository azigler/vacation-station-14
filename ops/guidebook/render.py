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


def _render_embed(elem: ET.Element) -> str:
    """Render an entity/reagent/etc embed.

    For `<GuideEntityEmbed>` we try to resolve the entity's Sprite via
    the module-level SpriteCache and emit an `<img>`. All other embed
    tags (reagent, group, discipline, lawset, etc.) still render as the
    v1 text pill — sprite resolution for those is out of scope for
    vs-mlg.

    Falls back to the text pill on any resolution failure so the build
    never crashes on a missing or malformed RSI.
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
</head>
<body>
<div class="layout">
  <aside class="sidebar">
    <a class="home" href="/">← Vacation Station 14</a>
    <h1><a href="index.html">Guidebook</a></h1>
    <nav class="toc">{toc}</nav>
  </aside>
  <main class="content">
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
</body>
</html>
"""


INDEX_BODY = """<p>The in-game Guidebook, rendered as a static site for reading outside the client.
Pick a topic on the left to get started, or jump to
<a href="NewPlayer.html">New Player</a> if you've never played before.</p>

<p class="note">Rendering is a minimal subset: text, cross-links, and
entity sprites. Reagent groupings, reaction graphs, and recipe tables are
not yet implemented — they render inline in the live game, which is still
the authoritative source.</p>

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


def build_toc(
    entries: dict[str, dict], labels: dict[str, str], current: str | None
) -> str:
    """Render the sidebar TOC tree."""
    roots = build_roots(entries)
    visited: set[str] = set()

    def render_node(eid: str) -> str:
        if eid in visited or eid not in entries:
            return ""
        visited.add(eid)
        e = entries[eid]
        label = html.escape(resolve_label(e, labels))
        cls = ' class="current"' if eid == current else ""
        children_html = ""
        if e["children"]:
            parts = [render_node(c) for c in e["children"] if c in entries]
            parts = [p for p in parts if p]
            if parts:
                children_html = "<ul>" + "".join(parts) + "</ul>"
        return f'<li><a href="{eid}.html"{cls}>{label}</a>{children_html}</li>'

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
    entries = load_entries(repo)
    labels = load_labels(repo)
    entry_ids = set(entries)

    out.mkdir(parents=True, exist_ok=True)
    (out / "style.css").write_text(STYLE_CSS, encoding="utf-8")

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
        page = PAGE_TEMPLATE.format(
            title=html.escape(title),
            toc=toc,
            crumbs=crumbs,
            body=body,
            source=source,
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
