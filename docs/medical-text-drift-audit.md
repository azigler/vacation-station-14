# Medical Text Drift Audit

Audit of in-repo medical prose (Fluent locale strings + guidebook XML) against
the authoritative YAML in `Resources/Prototypes/Reagents/`. The YAML — via its
`metabolisms.Bloodstream.effects` and conditions like `MobStateCondition`,
`TemperatureCondition`, `ReagentCondition`, `MetabolizerTypeCondition` — is
the single source of truth for reagent behaviour. Where prose disagreed with
YAML, the prose was rewritten. Wiki claims are informational only.

## Summary

- **26 common reagents** audited (the medic-facing set: Bicaridine, Bruizine,
  Lacerinol, Puncturase, Dermaline, Kelotane, Dylovene, Tricordrazine,
  Epinephrine, Inaprovaline, Dexalin, DexalinPlus, Ultravasculine, Arithrazine,
  Hyronalin, Sigynate, Siderlac, Leporazine, Pyrazine, Insuzine, Cryoxadone,
  Aloxadone, Doxarubixadone, Saline, Iron, Copper).
- **5 drifts fixed** on this branch: Tricordrazine desc, Cryoxadone activation
  temperature in the Cryogenics guidebook, Iron + Copper reagent descriptions
  (added blood-level interaction), Dexaline misspelling in MedicalDoctor.xml.
- **21 reagents clean** — prose already consistent with YAML within the
  tolerance of a short description.

## Findings table

| Reagent | Wiki / prior claim | YAML reality | In-repo text before | Fix status |
|---|---|---|---|---|
| Tricordrazine | "only works below 50 total damage" (wiki); "as long as the user is not heavily wounded" (in-repo) | `MobStateCondition: Alive` — any damage level, just not Critical / Dead | "Treats minor damage of all basic health types as long as the user is not heavily wounded." | **Fixed** — now "Heals minor brute, burn, and poison damage while the patient is alive, but has no effect on critical or dead patients." |
| Cryoxadone (guidebook) | "Cryoxadone works at under 170K" in Cryogenics.xml | `TemperatureCondition max: 213.0` | "Cryoxadone works at under 170K, but it is standard practice to set the freezer to 100K…" | **Fixed** — 170K -> 213K |
| Cryoxadone (reagent desc) | n/a | 213K temp gate | "only works in temperatures under 213K" | Clean |
| Iron | No prior medical hint in desc; MedicalDoctor.xml recommends "blood or iron" for bloodloss | `ModifyBloodLevel: 0.4` for non-arachnid metabolizers; `Poison: 0.1` for arachnids | "A silvery-grey metal which forms iron oxides (rust)…" — no medical mention | **Fixed** — appended "Replenishes blood in most species, but is mildly toxic to arachnids." |
| Copper | Purely metallurgical description | `ModifyBloodLevel: 0.4` for arachnids; `Poison: 0.1` for everyone else | "A soft, malleable, and ductile metal with very high thermal and electrical conductivity." | **Fixed** — appended "Replenishes blood in arachnids, but is mildly toxic to most other species." |
| Dexalin (guidebook spelling) | n/a | IDs are `Dexalin` / `DexalinPlus` | MedicalDoctor.xml used "Dexaline" twice | **Fixed** — Dexaline -> Dexalin |
| Bicaridine | "Highly effective at treating brute damage" | `EvenHealthChange Brute: -1.5`; OD ≥ 30u vomit; 15u+ asphyx/poison side effects | "An analgesic which is highly effective at treating brute damage…" | Clean |
| Bruizine | "Wildly effective at treating blunt force trauma" | `Blunt: -2.25`; OD ≥ 10.5u causes Poison | "wildly effective at treating blunt force trauma" | Clean |
| Lacerinol | "Heals slash trauma" | `Slash: -2`, minor Heat side effect; OD 12u+ Cold | "heals slash trauma" | Clean |
| Puncturase | "rebuild trauma caused by piercing damage, leaving a slight amount of tissue damage behind" | `Piercing: -2.5`, small `Radiation: 0.05`; OD 12u+ Blunt | matches — "slight tissue damage" = small radiation | Clean |
| Dermaline | "more effective at treating burn damage than kelotane" | Heat/Shock/Cold -1.5 each (Kelotane is -0.33 each) | matches | Clean |
| Kelotane | "Treats burn damage. Overdosing greatly reduces the body's ability to retain water." | Burn subtypes -0.33; OD 30u+ `SatiateThirst: -10` | matches | Clean |
| Dylovene | "treats toxin damage… Overdosing will cause vomiting, dizzyness and pain." | `Poison: -1`; OD 20u+ Blunt 2 + jitter + vomit + drunk | matches ("pain" = blunt, "dizzyness" = jitter/drunk) | Clean |
| Epinephrine | "keep a critical person from dying to asphyxiation while patching up minor damage during crit. Flushes heartbreaker toxin… may add histamine. Helps reduce stun time." | `MobStateCondition: Critical` + ≤ 20u: asphyx -3, brute/burn -0.5; OD 20u+ hurts; HeartbreakerToxin -2; stun/knockdown -0.75s | matches | Clean |
| Inaprovaline | "treat asphyxiation damage caused during critical states and reduce bleeding" | `MobStateCondition: Critical` -> Asphyxiation -2; `ModifyBleed: -0.25` | matches | Clean |
| Dexalin | "treating minor oxygen deprivation and bloodloss" | Asphyx -1, Bloodloss -0.5; OD 20u+ causes asphyx/cold damage | matches | Clean |
| DexalinPlus | "extreme cases of oxygen deprivation and bloodloss. Flushes heartbreaker toxin" | Asphyx -3.5, Bloodloss -3, HeartbreakerToxin -3 (conditional); OD 25u+ damage | matches | Clean |
| Ultravasculine | "quickly flushes out toxin while causing minor stress… Reacts with histamine, duplicating itself while flushing it out. Overdose causes extreme pain." | < 20u: Toxin -6 + Blunt +1.5; ≥ 20u: Toxin -2 + Blunt +6; consumes Histamine + replicates | matches | Clean |
| Arithrazine | "extreme case of radiation poisoning. Exerts minor stress on the body." | `Radiation: -3, Blunt: 1.5` | matches | Clean |
| Hyronalin | "weak treatment for radiation damage… Can cause vomiting." | `Radiation: -1`, vomit probability 0.02; OD 30u+ Heat +2 | matches within tolerance | Clean |
| Sigynate | "neutralizing acids and soothing trauma caused by acids" | `Caustic: -1.25`; side effects at 16u+/20u+/30u+ | matches | Clean |
| Siderlac | "powerful anti-caustic medicine derived from plants" | `Caustic: -5` | matches | Clean |
| Leporazine | "stabilize body temperature and rapidly cure cold damage… prevents the use of cryogenic tubes" | Cold -4, aggressive temperature adjustment toward 293.15K | matches — warming prevents cryo | Clean |
| Pyrazine | "heals burns from the hottest of fires. Causes massive internal bleeding when overdosed." | Heat -1; OD 20u+ Slash/Piercing 0.5 each (bleeding) | matches | Clean |
| Insuzine | "Rapidly repairs dead tissue caused by electrocution, but cools you slightly. Completely freezes the patient when overdosed." | `Shock: -1.5`, AdjustTemperature -2500; OD 12u+ Cold damage + AdjustTemperature -30000 | matches | Clean |
| Aloxadone | "treat severe burns and frostbite via regeneration… Works regardless of the patient being alive or dead." | `worksOnTheDead: true`, temp ≤ 213K, `Burn: -4.5` (covers Heat/Shock/Cold subtypes including frostbite) | matches | Clean |
| Doxarubixadone | "cryogenics chemical. Heals cellular damage caused by dangerous gasses and chemicals." | Temp ≤ 213K, `Cellular: -2` | matches | Clean |
| Saline | "treat dehydration or low fluid presence in blood" | `SatiateThirst: 6`, `ModifyBloodLevel: 6` | matches | Clean |

## Out-of-scope observations

These were noticed during the audit but not fixed here because they fall
outside the "reagent text vs YAML behaviour" scope of this branch:

- **MedicalDoctor.xml revival threshold** ("Defibrillator's can be used to
  revive patients under 200 total damage") — Not verified against the
  defibrillator component, and fixing it requires a separate code-side
  sanity check. Left as-is.
- **"Defibrillator's" possessive apostrophe typo** in the same file — Pure
  typo, not drift. Out of scope.
- **Flavorful side-effect omissions** — Many reagents have nuanced OD
  side-effects (e.g. Dermaline 10u+ asphyx/cold/blunt; Hyronalin 30u+ heat)
  that the short description elides. Tolerated where the top-level claim is
  still accurate; a reagent desc is not a full mechanics sheet.
- **Other locales** — en-US only. zh-Hans, fr, etc. have their own
  maintainers and were not touched.

## Upstream portability

All commits on this branch are scoped to `Resources/Locale/en-US/` and
`Resources/ServerInfo/Guidebook/Medical/`, with upstream-style subjects and
no VS14-specific trailers on the per-reagent commits. The branch
(`fix/medical-text-code-drift`) is safe to cherry-pick onto a fork of
`space-wizards/space-station-14`. Only the final summary commit carrying
this document + the `docs/upstream-sync.md` note references the internal
bead and should be dropped before any upstream PR.

## Methodology

1. Grepped `Resources/Locale/en-US/reagents/` and
   `Resources/ServerInfo/Guidebook/` for each common reagent.
2. Cross-referenced the YAML definition in
   `Resources/Prototypes/Reagents/medicine.yml` and
   `Resources/Prototypes/Reagents/elements.yml` — reading the full
   `metabolisms.Bloodstream.effects` block including `conditions`.
3. Classified as **drift** only where the prose made a falsifiable claim
   contradicted by the YAML (e.g. a threshold that doesn't exist, a
   temperature that doesn't match, a missing species interaction that is
   actively recommended elsewhere in the guidebook).
4. For genuinely vague prose ("useful for", "great for"), left alone even
   if the full mechanics are more nuanced.
