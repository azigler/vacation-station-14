# Incident template

Use this for writing up any notable incident: grief spree,
harassment report, exploit discovery, brigading attempt, public
drama, for-cause admin removal, hub-moderator correspondence.

## Why we write these

- **Consistency** — structured writeups stay searchable and
  comparable later
- **Pattern detection** — one griefer is a ticket; the same handle
  showing up across five incident docs is a pattern
- **Precedent** — "what did we do last time" is answerable in one
  grep, not three Discord searches
- **Accountability** — if someone disputes a call six months later,
  the doc is the record of why we decided what we decided

## Where they live

- **Routine tickets** (warns, short bans, no novel call): just the
  in-game ban record. Don't over-file.
- **Notable incidents**: written up by the responding admin and
  sent privately to the maintainer (storage detail in §Storage
  below). Filename: `incident-YYYYMMDD-short-slug.md`.
- **Player-facing summary** (if applicable): only the maintainer
  publishes redacted versions, at `/appeals` or via announcement.
  The full doc never leaves the maintainer's hands.

## When to write one

Write one if any of these apply; otherwise skip.

- Extended ban duration
- Permanent ban
- Hub-level (Wizden identity) escalation
- The decision set a new precedent (an outcome we'll want to
  reference next time)
- The incident became public (Discord drama, hub-mod ping, GitHub
  issue)
- For-cause admin removal (see [offboarding-checklist.md](./offboarding-checklist.md))
- Data privacy event (leak, unauthorized access, LEO request)
- Exploit or vulnerability disclosed

## Template

Copy the fenced block below, fill in, save as
`incident-YYYYMMDD-short-slug.md`, and send privately to the
maintainer.

````markdown
# Incident: [short title]

**Date**: YYYY-MM-DD  (primary event; if multi-day, note the
range in the summary)
**Filed by**: [admin name]
**Filed on**: YYYY-MM-DD HH:MM UTC
**Severity**: low / medium / high / critical
**Status**: open / resolved / monitoring / escalated  (lifecycle
state of the incident itself; not whether follow-ups remain — a
resolved ban can still have open monitoring follow-ups)

## Summary

Two or three sentences. What happened, who was involved (by
handle), what was the outcome. A reader skimming the archive
should get the shape of the incident from the summary alone.

## Timeline

Chronological, timestamped. UTC.

- `HH:MM` — event
- `HH:MM` — event
- `HH:MM` — admin action taken

Use Discord message links and ahelp IDs where available. Don't
paraphrase quotes; copy them verbatim and note `[sic]` for typos
if quoting directly matters. For non-English content, preserve
the original-language quote (don't translate inline) — some
harassment cases turn on specific words in specific languages.

## Parties involved

| Handle | Role             | Account identifiers                  |
|--------|------------------|--------------------------------------|
| ...    | Target           | Discord @X, hub ID Y, IP logged      |
| ...    | Reporter         | ...                                  |
| ...    | Responding admin | ...                                  |

## Evidence

- Ahelp transcripts (paste inline or attach as `.txt`)
- Screenshots (attach, don't embed — keeps the doc greppable)
- Chat log excerpts (verbatim, with Discord message link)
- Game logs (relevant admin-action lines, watchdog log excerpts)
- External links (archive.org copies preferred over live URLs for
  anything that might be deleted)

All evidence named, not described. "Screenshot A" not "a
screenshot from around 14:30."

## Decision

- **Action taken**: warn / kick / temp-ban (duration) / permaban /
  hub-ban / other
- **Decided by**: [admin name]
- **Rationale**: one paragraph. Reference specific rule (e.g.,
  "rule A1 harassment") and the evidence items justifying it.
- **Precedent**: matches [prior incident] OR new — expect future
  similar cases to match this one.

## Player communication

Verbatim, what was said to the player(s).

- **Ban message**: `...`
- **Ahelp reply**: `...`
- **Discord notification**: `...` (if any)

If communication differed from the internal decision (we said
"temp-ban" but the real reason was suspicion of X, which we
didn't want to tip them off about), note that here.

## Appeal

- [ ] Is the ban appealable? (default yes; see
      [sanctions.md](./sanctions.md))
- [ ] Has the player appealed? Link the appeal thread.
- [ ] Appeal outcome: upheld / reduced / overturned. Reasoning.

## Follow-ups

- [ ] Any follow-up actions to take
- [ ] Any ongoing monitoring (e.g., watch for ban evasion from
      related accounts)
- [ ] Any policy changes this incident surfaced (file a bead)

## Lessons

One or two paragraphs. What did we learn? What would we do
differently next time? This is the part that makes the archive
useful a year from now — without it, incident docs are just ban
records.
````

## Notes on writing

- **Timestamps UTC, always.** Mixed timezones are unreadable.
- **Handles, not real names.**
- **Verbatim quotes.** Paraphrasing corrupts the record. If a
  player said something awful, the doc says that awful thing.
  It's not our job to clean it up.
- **No emotional language about the parties.** "X was being a
  dick" is not a useful record. "X sent three messages calling Y
  a [slur]" is.
- **Quick is fine.** A rough timeline + decision + evidence is
  much more useful than a polished writeup that never gets filed.
  Aim for "complete promptly" not "polished slowly."
- **Redact for sharing.** Only the maintainer shares redacted
  copies outside the admin team (with the player, with the hub,
  with the public). The full doc stays with the maintainer.

## Storage

Send incident docs privately to the maintainer (DM is fine for
now). The maintainer keeps the canonical copy. One file per
incident — never in the public repo or anywhere with broader
access. Incident docs contain private
account data and ahelp content; treat them as confidential.
