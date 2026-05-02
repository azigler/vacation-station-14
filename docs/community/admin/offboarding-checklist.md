# Admin offboarding checklist

When an admin leaves the team — voluntarily, on hiatus, or
for-cause — the maintainer works the relevant section below.
Most of this doesn't apply yet (one admin), but lives here so we
have a procedure when the team grows.

## Common steps (any path)

- [ ] Remove Discord `@Admin` role
- [ ] Remove the admin row from the postgres `admin` table
- [ ] Revoke SS14.Admin panel access
- [ ] Remove from any admin-only Discord channels
- [ ] Revoke any host / repo / watchdog credentials they had

## Voluntary step-down

Assume good faith. The admin is doing the project a favor by
stepping down cleanly rather than ghosting.

- [ ] Short thank-you in `#admin-only`
- [ ] Optional public thank-you in `#announcements` if they had a
      visible role
- [ ] Exit check-in (DM): what worked, what didn't, anything the
      team should know? Notes go to a private file.

## Hiatus (returning later)

Distinct from step-down. The admin plans to come back, so access
posture differs — keep the Discord `@Admin` role and admin-channel
access (situational awareness when they return matters), but pause
in-game admin verbs (postgres admin row removed, SS14.Admin panel
revoked) until they're back and ready.

- [ ] Pause in-game admin permissions; keep Discord access
- [ ] Re-read expectations.md + sanctions.md after a long break;
      otherwise straight back in when they return

## For-cause removal

The hard path. Use only when there's a specific, documented reason
(breach of admin conduct, privacy violation, repeated violations
after warning).

- [ ] Maintainer writes the reason as an incident doc (see
      [incident-template.md](./incident-template.md))
- [ ] Pause before executing, unless safety/privacy is actively
      compromised (doxxing, data leak, active harassment from the
      admin role) — those act immediately
- [ ] Conversation with the outgoing admin if safe and practical:
      state the decision, hear their side, pause if new info
      changes the call
- [ ] Audit their recent admin actions — bans on players they
      should have stayed off, permission grants, watchdog activity,
      log channels
- [ ] Rotate every shared credential they had access to: watchdog
      API token, Discord webhook URLs, bot tokens, Grafana admin
      password if applicable
- [ ] Public handling: announce the departure depending on the
      sensitivity of the situation and those involved

## Emergency immediate removal

If the admin is actively causing harm right now (live grief as
admin, doxxing, data exfiltration), skip all "wait" and "talk
first" steps:

1. Kick from Discord, strip roles
2. Revoke SS14.Admin + postgres admin row
3. Rotate shared credentials before anything else
4. Ban from Discord + game if warranted
5. Capture timestamps as you go (Discord message links, game-server
   timestamps) — don't try to reconstruct after the fact
6. Audit their recent actions
7. Have the conversation later

Speed over completeness. Document after.
