---
description: VS14 brand identity — visual lens for logos, icons, hero illustrations, splash art, social cards, and any rendered asset. Embodies the maintainer-pinned Frutiger Aero × Silicon Dreams aesthetic with autumn coral palette and ground-level rolling-hills composition. Load whenever generating, evaluating, or iterating on VS14 visual assets via /openrouter (nano-banana) or by hand. Pairs with /impeccable for design craft and /vs14-voice for written-content discipline.
---

# VS14 brand

Visual identity lens for VS14. Every rendered asset — logo, icon,
hero, splash, social card, in-game branding — inherits from this
prompt.

This is the **machine-readable** brand source. The
[/vs14-voice](../vs14-voice/SKILL.md) skill is the written-content
equivalent.

## Maintainer-pinned aesthetic (locked 2026-05-03 via vs-7ns interview)

- **Frutiger Aero × Silicon Dreams** — late-1990s / early-2000s
  3D-render surrealism (Bryce-3D, Poser) crossed with Frutiger
  Aero's grounded optimistic photorealism (dewy water beads,
  glossy leaves, soft volumetric light).
- **Autumn coral + earthy pastels + aquatics** — soft coral, rust,
  sage, teal, aquamarine. Earthy with jewel-tone undertones. Never
  neon, never corporate-slick.
- **Stardew Valley adjacent** — autumnal warmth, hand-finished
  feel. Stardew is a tonal reference, NOT a treatment reference —
  no pixel art.
- **Ground-up rolling hills, NEVER cosmic** — this is the inversion
  of the SS14 space-sim trope. The work is anchored on earth,
  looking up at land or down at dewy ground. No starfields, no
  planets, no checker-floor surrealism (Silicon Dreams' biggest
  motif we're dropping).

## The base prompt (the "lens")

Every asset prompt prepends this block. It's the stable identity
that keeps generated assets visually consistent over time.

```
Aesthetic: Frutiger Aero meets Silicon Dreams 3D-render era — late
1990s and early 2000s software-box surrealism, but anchored to the
earth instead of cosmic space. Soft autumn coral and rust tones
blended with sage, teal, and aquamarine. Earthy pastel palette with
jewel-tone undertones — never neon, never corporate-slick.

Composition: ground-level perspective looking up at rolling autumnal
hills under a soft golden-hour sky. Dewy moss, glossy leaves with
water beads, fallen leaves, occasional ripe apple or fungal cluster.
Subtle lens flare from a low warm sun. NEVER cosmic, NEVER space,
NEVER starfields — the work is anchored on earth, looking up at the
land or down at the ground.

Rendering: 3D-rendered with that Bryce-3D / Poser late-90s feel —
slightly glossy plastic surfaces, raytraced reflections in dewdrops,
soft volumetric light. Hand-finished, with intentional imperfection
(not AAA-polished, not AI-clean).

Mood: dreamy but grounded. Optimistic but earnest. Cozy but not
twee. The feeling of taking a slow walk on a low-stakes autumn day.
Stardew-adjacent warmth without the pixel-art treatment.
```

## Universal anti-patterns

Any asset prompt should also include this block (or quote it
back when reviewing a generated asset):

```
AVOID: cyan-on-dark, neon, AAA-game polish, corporate gradients,
generic AI aesthetic, space / starfields / cosmos, military imagery,
checker-floor surrealism, Y2K chrome, gradient text, glassmorphism,
Inter / Helvetica typography readouts inside the image, pixel art,
hands with six fingers, AI-shape watermarks.
```

## Asset composition templates

Each asset type adds a composition block on top of the lens.

### Logo (1:1)

> A circular emblem composition. The rolling hill silhouette wraps
> the lower curve of the frame. Wordmark-friendly negative space at
> the top of the frame for the words "Vacation Station 14" to be
> overlaid. A single focal motif (a leaf / a dewdrop / a fallen
> apple / a fungal cluster) anchors the center. Soft golden-hour
> palette throughout.

### Icon (1:1)

> A single object floating gently in a soft pastel-mist void —
> [the chef's hat / a wrench / a beaker / a fish / a microwave /
> a potted plant]. Same palette, lighting, and rendering as the
> logo for visual consistency. The object reads at small sizes
> (32px tile).

### Hero illustration (16:9 or 21:9)

> A wide ground-level vista. Rolling autumn hills under a soft
> sky. A small structure or meandering path leading the eye into
> the distance. Negative space in the upper-left for a headline
> overlay. Subtle motion or atmospheric depth.

### Background tile (seamless)

> A subtle dewy-moss texture. Repeatable / seamless. Low contrast
> so text reads on top. Soft sage-coral wash. No focal subject —
> this is texture, not subject.

### Social card (1.91:1, OpenGraph dims)

> The hero composition compressed: rolling hills + path or focal
> structure on the right two-thirds; left third reserved for
> wordmark + tagline overlay. Same palette and rendering.

## Generation flow

1. **Confirm the user explicitly asked.** This skill never fires
   from autonomous loops. See /openrouter cost discipline.
2. **Compose the prompt**: `<brand base prompt>` + `<asset
   composition>` + `AVOID block`. Adjust subject specifics to taste.
3. **Render at 1K** for iteration (~$0.004 per image). Save to
   `assets/brand/iterations/<asset>-vN.png`.
4. **Iterate**: review with the user, refine the composition or
   palette emphasis, re-render. Don't loop without explicit ask.
5. **When a candidate is approved**, render the final at 2K or 4K
   and **promote** to:
   - `Resources/Textures/_VS/branding/` — in-game use (RSI sprites
     where appropriate; PNG for splash / loading)
   - `web/public/branding/` — website use (when vs-2dr ships)
   - GitHub repo social card — via repo Settings → Social preview

## Cost reference (nano-banana 2)

| Size | Approx cost / image |
|---|---|
| 1K (default) | ~$0.004 |
| 2K | ~$0.012 |
| 4K | ~$0.04 |

Iterate at 1K. Only render finals at 2K-4K once a direction is
locked.

## File-storage convention

```
assets/
  brand/
    iterations/        # noisy iteration output (gitignored)
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
The maintainer's interview pinned:

- NOT generic (no Inter, Roboto, Lato, Open Sans, Montserrat —
  these read as AI-default)
- Readable / WCAG-compliant
- With personality

Candidate type pairings to evaluate when website-time comes:

- Display: Frutiger (the actual font, since the aesthetic is named
  after it) / Recoleta / DM Serif Display / Atkinson Hyperlegible
- Body: Atkinson Hyperlegible / Public Sans / DM Sans / Comfortaa

Decision deferred until vs-2dr Phase 1 / vs-7ns logo lands. The
typeface should harmonize with the chosen logo, not the other way
around.

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

## See also

- [/openrouter](../../../../.claude/skills/openrouter/SKILL.md) —
  image generation API; the skill that this skill drives
- [/impeccable](../../../../.claude/skills/impeccable/SKILL.md) —
  design library (typography, color, motion, accessibility)
- [/vs14-voice](../vs14-voice/SKILL.md) — written-content lens;
  parallel skill for copy
- vs-7ns — current brand-identity bead; carries the aesthetic
  interview answers in --notes
