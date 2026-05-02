# VS14 admin docs

Internal reference for how we run admin work on VS14: what admins do,
how to handle tickets, how the ban tiers work, how to onboard the
next person, how to write up the rare incident that needs a record.

## Server rules

The actual rules players play under live in
[`docs/community/rules.md`](../rules.md). Start there if you want to
know what we enforce. This folder is the operational companion —
sanctions matrix, training, onboarding, incident templates — for how
we enforce it.

## Who this is for

Admins, recruits we're considering inviting, and anyone curious about
how we handle admin work here.

## Contents

1. **[expectations.md](./expectations.md)** — what admins do and
   don't do, escalation ladder, privacy, conduct standards.
2. **[training.md](./training.md)** — tools you have, how to start,
   ongoing admin life.
3. **[onboarding-checklist.md](./onboarding-checklist.md)** —
   identity + access, credentials, reading acknowledgments, intro.
4. **[offboarding-checklist.md](./offboarding-checklist.md)** —
   voluntary step-down or hiatus, for-cause removal, emergency
   removal.
5. **[sanctions.md](./sanctions.md)** — rule tiers, ban-duration
   matrix, ban categories, appeals process, hub-escalation criteria.
6. **[incident-template.md](./incident-template.md)** — when to
   file one, the template itself, notes on writing, storage.

## Where this shows up on the website

These pages don't exist yet — they're the planned mirrors once the
website (vs-2dr) ships:

- `/rules` — will publish from [`docs/community/rules.md`](../rules.md)
  (this folder references those rule numbers in `sanctions.md`)
- `/appeals` — will derive from `sanctions.md` appeals section
- MOTD — short pointer to `/rules`, `/discord`, `/appeals`

Source-of-truth docs are in `docs/community/`. When they change,
update any website mirrors; when the website is edited first,
backfill here.

## Not in this folder

- **TOS / privacy / DMCA** — website-published, drafted separately
  (the legal backstop for our authority to sanction).
- **Moderation tooling** — the SS14.Admin web panel and the Discord
  bot are deployed services, not docs. SS14's hub ban-request
  process lives upstream at Wizards' Den.
- **Code contribution guidelines** — `CONTRIBUTING.md` at the repo
  root.
