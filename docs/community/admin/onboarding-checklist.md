# Admin onboarding checklist

Run through this when a new admin joins. The maintainer owns the
list and walks the recruit through each section.

## Identity + access

- [ ] Identity verified (ask them to post a short string in
      `#admin-only` from both their Discord and their in-game hub ID)
- [ ] Discord `@Admin` role + admin-channel permissions
- [ ] In-game admin permissions granted in the postgres `admin`
      table (via the SS14.Admin panel if live; SQL via the
      maintainer otherwise)
- [ ] SS14.Admin web panel login tested

## Credentials

- [ ] 2FA enabled on Discord (self-attested — required for admins)
- [ ] 2FA enabled on GitHub (self-attested — if granted repo write access)

## Reading

- [ ] Recruit has read and acknowledged each of:
      - [ ] [expectations.md](./expectations.md)
      - [ ] [sanctions.md](./sanctions.md)
      - [ ] [training.md](./training.md)
      - [ ] [incident-template.md](./incident-template.md)
      - [ ] [Server rules](../rules.md) (`/rules` on the website)
      - [ ] Terms of Service (`/tos`)
- [ ] Ack logged somewhere referencable (a DM with the maintainer
      is fine)

## Training

- [ ] Admin-tool tour completed (see training.md "Tools you have")
- [ ] First-tickets plan agreed — tag-in mode, ticket logging, etc.
      (see training.md "How to start")

## Introduction

- [ ] Recruit introduces themselves in `#admin-only` — name,
      timezone, availability, what they're most confident on and
      what they're most unsure about

## Sign-off

The maintainer marks the checklist complete somewhere referencable
(a DM, a post, a git commit). That moment is the formal "you are
an admin now" — not the Discord role assignment earlier in the list.
