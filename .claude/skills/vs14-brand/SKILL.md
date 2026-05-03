---
description: VS14 brand identity — visual lens for logos, icons, hero illustrations, splash art, social cards, and any rendered asset. Embodies the maintainer-locked retro 8-bit + CRT-bezel aesthetic — pixel-art native, NES-era palette, vintage hardware framing. Load whenever generating, evaluating, or iterating on VS14 visual assets via /openrouter (nano-banana) or by hand. Pairs with /impeccable for design craft and /vs14-voice for written-content discipline.
---

# VS14 brand

Visual identity lens for VS14. Every rendered asset — logo, icon,
hero, splash, social card, in-game branding — inherits from this
prompt.

This is the **machine-readable** brand source. The
[/vs14-voice](../vs14-voice/SKILL.md) skill is the written-content
equivalent.

## Maintainer-locked aesthetic (locked 2026-05-03 via vs-qkr concept-C exploration)

- **Retro 8-bit + CRT bezel** — late-1980s / early-1990s console
  video-game art, NES-era chunky pixel art rendered diegetically
  on a CRT television. The CRT bezel is the brand wrapper —
  every asset reads as if photographed FROM a vintage screen,
  not generated as a flat illustration.
- **NES palette** — royal blue, pixel white, mustard-yellow drop
  shadow, vermillion red accent. Bold and saturated, never neon,
  never pastel, never AAA-game polish.
- **Pixel-art is the native genre** — SS14 IS rendered in pixel
  art in-game. The brand aligns with that genre instead of
  fighting it with a 3D-render lens. The contrast IS the brand:
  photorealistic CRT bezel framing NES-resolution pixel-art
  interior.
- **Cosmic IS allowed inside the screen** — starfields, pixel
  rockets, pixel space-stations all read as native habitat at
  NES resolution, not corporate sci-fi cliché. The earlier
  "never cosmic" rule was specific to the abandoned 3D-render
  lens; in pixel-art, the cosmic is part of the genre.
- **Stardew-adjacent warmth, hand-finished feel** — casual,
  nostalgic, fun. The energy of finding an old console at a
  thrift store and being surprised it still works. Tonal
  reference, not treatment reference.

## The base prompt (the "lens")

Every asset prompt prepends this block. It's the stable identity
that keeps generated assets visually consistent over time.

```
Aesthetic: late 1980s / early 1990s console video game, NES-era
chunky pixel art rendered diegetically on a CRT television. The
CRT bezel is the brand wrapper — every asset reads as if
photographed FROM a vintage screen, not generated as a flat
illustration. The contrast between photorealistic CRT hardware
and NES-resolution pixel-art interior IS the brand.

Palette: NES royal blue (#1d4ed8 / #2563eb range), pixel white,
mustard-yellow drop shadow (#facc15 / #eab308 range), vermillion
red accent (#dc2626 / #b91c1c range). Bold, saturated, never
neon, never pastel. Black starfield backgrounds inside the
screen are welcome. The CRT bezel is warm-gray plastic with
subtle highlights — soft-finished, not chrome.

Composition: anchored on the CRT screen as the brand wrapper.
Inside the screen: pixel-art subjects at NES resolution (chunky,
1-2px detail max, no anti-aliasing within the pixel grid). The
TV sits in a mild 3/4 perspective on a warm desk surface,
optionally with an NES-era controller in the foreground for
specificity. The screen has subtle phosphor glow and faint
horizontal scanlines — the hardware is visible.

Rendering: photorealistic CRT (subtle phosphor glow, faint
scanlines, slight curvature, warm vignette at corners) framing
NES-era pixel-art content. Pixel content is rendered at LOW
resolution and stays low — no smoothing, no anti-aliasing
within the pixel grid, no high-poly 3D shading on supposedly
pixel objects.

Mood: nostalgic, casual, fun. The energy of finding an old
console at a thrift store and being surprised it still works.
Stardew-adjacent autumnal warmth, but in pixel-art-native genre
rather than 3D-render-of-pixel-art aesthetic.
```

## Universal anti-patterns

Any asset prompt should also include this block (or quote it
back when reviewing a generated asset):

```
AVOID: smooth-shaded 3D models, AAA-game polish, raytraced
reflections, motion-blur cosmic rendering, glowing energy
effects, generic AI sci-fi, military imagery, Y2K chrome,
glassmorphism, gradient text, corporate gradients, neon
accents, cyan-on-dark dashboards, Inter / Helvetica typography
readouts inside the image, hands with six fingers, AI-shape
watermarks, anti-aliasing within the pixel grid (kills NES
authenticity), vector / flat illustration without the CRT
frame (loses the genre wrapper), Frutiger Aero (the abandoned
direction), pastel coral / sage / aquamarine (the abandoned
palette), 3D-rendered glossy plastic / chrome / glass surfaces.
```

## Asset composition templates

Each asset type adds a composition block on top of the lens.

### Logo (horizontal, ~5:3 — primary)

The primary logo is the inner-screen rectangle of the canonical
brand image — NES-era pixel-art "VACATION STATION 14" wordmark
in chunky white letters with mustard-yellow drop shadow, set in
a slight italic-feel forward angle. To the right: a pixel rocket
and a pixel space-station emerging from the wordmark. To the
left: vermillion red horizontal ribbon stripes (vintage arcade
box-art). Royal blue gradient bottom, black starfield top.
Composition fills the image edge-to-edge.

The canonical version lives at `assets/brand/finals/logo-primary.png`
(cropped from the concept-C 5-concept exploration batch). Use it
as the **style ref** for every downstream asset prompt.

### Logo (full bezel — 4:3 hero variant)

Same wordmark composition as above but rendered inside the full
CRT bezel + NES controller in foreground on a warm desk surface.
Used as hero illustration / social card / launcher splash.

### Icon (1:1)

A CRT TV in mild 3/4 perspective, screen displaying a single
NES-era pixel object: pixel chef's hat, pixel wrench, pixel
beaker, pixel fish, pixel microwave, pixel potted plant, pixel
toolbox, pixel jukebox, etc. Same warm-gray bezel, faint
scanlines, mustard-yellow accent on the bezel border or stand.
Object reads at small sizes (32px tile).

### Shield / badge (3:1 to 5:1)

GitHub-shields.io-style, but rendered in NES pixel-art aesthetic.
Two-tone blocky rectangle with chunky pixel text — NES royal
blue background, pixel-white label text, mustard-yellow drop
shadow on key letters. Optional thin 1px CRT-scanline overlay
for genre-coherence. Used for README badges + website chip rows.

### Hero illustration (16:9 or 21:9)

Full CRT scene — bezel + screen + controller + warm desk
surface, optional second-person POV (player's hand on the
controller). Screen content varies by use case (logo for
landing page, in-game pixel scene for feature panels). Negative
space in the upper-left or above the TV for headline overlay.

### Background tile (seamless)

Subtle horizontal CRT-scanline overlay at low opacity, OR
NES-era dot-matrix dither in royal blue. Repeatable / seamless.
Low contrast so text reads on top. NOT a focal subject — this
is texture, not subject.

### Social card (1.91:1, OpenGraph dims)

The hero composition compressed: CRT TV + controller on the
right two-thirds; left third reserved for wordmark + tagline
overlay in the same NES palette.

## Generation flow

1. **Confirm the user explicitly asked.** This skill never fires
   from autonomous loops. See /openrouter cost discipline.
2. **Compose the prompt**: `<brand base prompt>` + `<asset
   composition>` + `AVOID block`. Adjust subject specifics to taste.
3. **Pass `assets/brand/finals/logo-primary.png` as `--ref`** —
   the canonical style anchor. For downstream assets, this is
   non-negotiable; text prompts alone collapse to AI defaults.
4. **Render at 1K** for iteration (~$0.07 per image). Save to
   `assets/brand/iterations/<asset>-vN.png`.
5. **Iterate**: review with the user, refine the composition or
   palette emphasis, re-render. Don't loop without explicit ask.
6. **When a candidate is approved**, render the final at 2K or 4K
   and **promote** to:
   - `assets/brand/finals/` — committed, canonical
   - `Resources/Textures/_VS/branding/` — in-game use (RSI sprites
     where appropriate; PNG for splash / loading)
   - `web/public/branding/` — website use (when vs-2dr ships)
   - GitHub repo social card — via repo Settings → Social preview

## Multi-ref pattern (load-bearing)

For any asset other than the primary logo itself:

```bash
~/.claude/skills/openrouter/openrouter-image.sh \
  "<brand base prompt> <asset composition> <subject> <AVOID block>" \
  ./assets/brand/iterations/<asset>-vN.png \
  --ref ./assets/brand/finals/logo-primary.png \
  --ref ./Resources/Textures/<sprite>.rsi/icon.png \
  --aspect 1:1 --size 1K
```

Style ref FIRST (logo-primary), content ref SECOND (the SS14
sprite or other subject). Order matters — first ref tends to
dominate the aesthetic.

## Cost reference (nano-banana 2 — measured 2026-05-03)

| Size | Approx cost / image |
|---|---|
| 1K (default) | ~$0.07 |
| 2K | ~$0.20 (estimate; scales with output token count) |
| 4K | ~$0.50+ (estimate) |

Image-output tokens are billed at roughly $61/M, far higher than
the model card's $3/M output rate suggests. Iterate at 1K; only
render finals at 2K-4K once a direction is locked. ~14 images per
USD at 1K.

The iteration arc that landed on concept-C consumed ~$4.65 across
~66 generations. Future corpus regens should fit in <$1.

## File-storage convention

```
assets/
  brand/
    iterations/        # noisy iteration output (gitignored)
      old-frutiger-finals/   # archived prior-direction assets
      concepts/              # 5-concept exploration batch
    finals/            # selected candidates (committed)
Resources/
  Textures/
    _VS/
      branding/        # in-game use, ratified finals only
web/                   # (forthcoming via vs-2dr)
  public/
    branding/          # website use
```

`assets/brand/iterations/` is gitignored. Only finals get
committed.

## Typography (open question)

The brand prompt focuses on rendered assets — but VS14 also needs
typography for the website (vs-2dr) and any in-image text overlays.
The retro-pixel direction reframes the type pairings:

- NOT generic (no Inter, Roboto, Lato, Open Sans, Montserrat —
  these read as AI-default)
- Readable / WCAG-compliant
- With personality

Candidate type pairings to evaluate when website-time comes:

- Display: Press Start 2P (NES-era pixel font) / VT323 (CRT
  terminal) / Major Mono Display / Recoleta (warm contrast pair)
- Body: Atkinson Hyperlegible / Public Sans / DM Sans / Comfortaa

A pixel-display font for headlines paired with a clean readable
body font gives the retro-game-on-modern-website contrast the
brand wants. Decision deferred until vs-2dr Phase 1.

## Anti-patterns specific to brand work

- **Generating without saving.** A generated image you didn't
  save is wasted credits.
- **Re-prompting without changing anything.** If a generation
  came back wrong, ask the user before re-firing — the new
  generation should change a specific axis (palette, composition,
  texture), not just re-roll.
- **Drift from the lens.** Per-asset prompts should not contradict
  the base lens. If you find yourself rewriting the lens in an
  asset prompt, raise it for an explicit lens revision instead.
- **Final-as-finished.** A candidate that passes maintainer review
  is "approved for promotion to finals/", not "the brand is done."
  The lens is the brand. Assets are applications of the lens.
- **Skipping the multi-ref pattern.** Text prompts alone collapse
  to AI defaults. Without `logo-primary.png` as a style ref,
  generations drift back toward generic-AI pixel art rather than
  the specific NES + CRT-bezel direction.
- **Anti-aliasing within the pixel grid.** A common AI-default
  drift — the model wants to "smooth" the pixel content. Call
  this out explicitly in every prompt; the AVOID block names it.

## See also

- [/openrouter](../../../../.claude/skills/openrouter/SKILL.md) —
  image generation API; the skill that this skill drives
- [/impeccable](../../../../.claude/skills/impeccable/SKILL.md) —
  design library (typography, color, motion, accessibility)
- [/vs14-voice](../vs14-voice/SKILL.md) — written-content lens;
  parallel skill for copy
- vs-7ns — current brand-identity bead; carries the locked
  aesthetic notes
- vs-qkr — sub-bead carrying the iteration log + concept-C
  lock-in rationale
