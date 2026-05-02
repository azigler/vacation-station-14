# VS14 sanctions

This is the reference doc for "what's the ban duration?" and "can
this be appealed?" The player-facing version (ban-message text +
appeals process) is derived from this doc but lives on the website.

## The four-tier rule structure

VS14 rules are organized into four tiers. Each tier has its own
typical sanction posture.

| Tier | Name                         | Example violations                              | Default posture        |
|------|------------------------------|-------------------------------------------------|------------------------|
| A    | Community Rules              | Harassment, hate speech, slurs, doxxing, NSFW   | Zero-tolerance, hub-escalate |
| B    | Game Server Rules            | IC/OOC mixing, meta-grudging, powergaming, self-antag | Graduated, usually kick/short-ban first |
| C    | Command / Antag Guidelines   | Bad-faith captain, antag-with-no-valid-gimmick  | Role removal, rarely a ban |
| S    | Silicon Rules                | Ignoring AI laws, bad-faith borg                | Role removal, warnings, rare bans |

The letters match the rule numbering on `/rules`. An admin ticket
referencing "rule A1" points at Community Rules #1 (harassment).

### Where the rule text lives

This doc references rules by their tier-and-number labels (e.g.,
"rule A1" = Community Rules #1). The actual text of each rule lives
in `docs/community/rules.md` and mirrors to `/rules` on the website.

## Default duration matrix

These are **defaults, not mandates**. Deviations are fine with
documented reasoning. Duration goes up with repeat offense, bad
faith, and severity; goes down with good faith, newness, and
context ambiguity.

| Violation shape                                       | 1st offense              | 2nd offense              | 3rd offense+             |
|-------------------------------------------------------|--------------------------|--------------------------|--------------------------|
| **Raiding / brigading (A0)**                          | Permaban + hub-escalate  | N/A                      | N/A                      |
| **Harassment / slurs / hate speech / bigotry (A1)**   | Permaban                 | N/A                      | N/A                      |
| **Doxxing / privacy violation (A2)**                  | Permaban + hub-escalate  | N/A                      | N/A                      |
| **NSFW / sexually explicit content (A3)**             | Warning + kick           | 1-week ban               | Permaban                 |
| **Age-floor violation (A4)**                          | Permaban                 | N/A                      | N/A                      |
| **Ban evasion (A5)**                                  | Permaban (both accounts) | N/A                      | N/A                      |
| **Exploit abuse (A6)**                                | 1-week ban + disclose    | Permaban                 | N/A                      |
| **Spam / OOC disruption (A7)**                        | Mute + warning           | 1-day ban                | 1-week ban               |
| **Breaking IC/OOC for advantage (B1)**                | Warning                  | Warning or short ban     | 1-week ban               |
| **Powergaming (B2)**                                  | Warning                  | 1-day ban                | 3-day ban                |
| **Griefing / self-antag (B3)**                        | 1-day ban                | 3-day ban                | 2-week ban → permaban    |
| **Ignoring ahelp (B4)**                               | 1-day ban                | 1-week ban               | Permaban                 |
| **Metacomms (B5)**                                    | Warning                  | 1-day ban                | 1-week ban               |
| **Command/security role abuse (C1)**                  | Role removal + warning   | Role whitelist removal   | Job ban for that role    |
| **Prisoner escape without IC reason (C2)**            | Warning + return to brig | Role ban (prisoner)      | Role ban (prisoner)      |
| **Antagonist guideline violation (C3)**               | Warning                  | 1-day ban                | Antag role ban           |
| **Silicon law violation (S-tier)**                    | Warning + role removal   | Silicon job ban          | Silicon job ban (permanent) |
| **Good-faith exploit disclosure**                     | No ban; thanks           | —                        | —                        |

**Important**: the A-tier permabans are for the behavior, not the
pattern. First-offense harassment with slurs is a permaban on first
offense. "1st offense" in the table just means "we've never seen
this player do this before" — not that we give three strikes.

**Silicon (S-tier) sanctions are admin-call.** The S-row above is a
starting bound. Actual sanction depends on which law was violated
(S4 willingly letting laws change is much sharper than S7 interpretation
drift), the severity, and the in-round impact. Use the matrix as a
calibration anchor, not a policy.

## Factors that bump UP severity

- Clear bad faith (e.g., "I did it because I wanted to get banned")
- Targeting a specific player or group repeatedly
- Admin evasion (logging out mid-ahelp, creating alt accounts)
- Previous ban history on VS14
- Hub-visible behavior (affecting our hub-listing reputation)
- Violating rules after they were specifically explained to the
  player by an admin

## Factors that bump DOWN severity

- Self-reported the violation before an ahelp was filed
- Took responsibility in the ahelp, engaged in good faith
- Prior clean record over many hours of play

## Ban categories

| Category          | Scope                                          | Appealable?              |
|-------------------|------------------------------------------------|--------------------------|
| Warn              | Ticket-only, visible to player                 | N/A                      |
| Job ban           | Specific job (e.g., "no Captain for a while")  | Yes, after a cooldown    |
| Round ban         | Kicked from current round only                 | N/A                      |
| Temp ban          | Short-term, auto-expires                       | Yes, anytime             |
| Long temp ban     | Longer-term, auto-expires                      | Yes, after a cooldown    |
| Permaban (server) | Permanent, VS14 only                           | Yes, after a long cooldown |
| Hub-level ban     | Permanent, requested via Wizden hub            | Via Wizden only          |

Hub-level bans are not unilateral — we request them, Wizden
evaluates. Only warranted for A-tier incidents with evidence strong
enough to survive the hub-mod review.

## Appeals

### Process

1. Banned player files an appeal at `/appeals` on the website.
2. The banning admin (or another admin if they're unavailable)
   reads the appeal promptly and acknowledges.
3. Reviewing admin reads the incident doc (if any), the chat logs,
   and the ahelp transcript. Does NOT rely on memory.
4. Decision posted in-thread. One of:
   - **Upheld** — the ban stands. One-paragraph explanation.
   - **Reduced** — duration cut or converted to a job ban. Explain.
   - **Overturned** — ban lifted. Explain, apologize if we got it
     wrong, update the incident doc.
5. Player can re-appeal once more if new evidence surfaces.
   Otherwise the decision stands.

### Appeals we don't entertain

- A-tier violations (harassment, slurs, doxxing, ban evasion) until
  enough time has passed. "I've changed" doesn't work fast.
- Ban evasion cases. The evasion itself forecloses the appeal.
- Rage appeals ("you're a fascist admin"). Ask the player to try
  again when calmer.
- Appeals from accounts flagged for hub-level issues. Route to
  Wizden.

### Tone

- Admins write appeal responses in a neutral, professional voice.
  No snark, no "well, actually," no lecturing.
- Thank the player for appealing, even if we uphold.
- Acknowledge what the player said in their appeal specifically —
  don't reply with a template.
- Keep replies short. 2-4 paragraphs. Longer replies read as
  defensive.

## Escalation to Wizden hub

Request a hub-level identity ban only when all of these are true:

- The violation was A-tier (harassment, slurs, doxxing, raiding)
- Evidence is strong enough to share publicly (chat logs,
  screenshots, timestamps)
- The behavior has either continued across servers or is bad enough
  that a single-server ban is insufficient (threats, coordinated
  harassment, illegal content)
- The maintainer is willing to put their name on the request — this
  is not a snap call

Hub-escalation request format:

1. Maintainer (only the maintainer) files the request using the
   Wizden hub-ban-request process.
2. Full evidence attached (redacted of any information the hub
   doesn't need).
3. Player is NOT notified we're escalating — the hub's
   investigation handles that.
4. We abide by the hub's decision regardless of outcome.

## Precedent and consistency

When making a novel call (something not clearly covered by the
matrix), write an incident doc (see
[incident-template.md](./incident-template.md)) and flag it as
precedent-setting. The next admin facing a similar case should
find the precedent, match the call, and link the prior incident
in their new incident doc. This is how the matrix evolves.

The maintainer periodically reviews accumulated precedents and
updates this document.

## Policy for contentious decisions

When a decision feels politically charged or genuinely ambiguous:

- Default to the **milder option**. It's much easier to escalate
  later than to climb down from a too-harsh call.
- **Pause before acting** for non-emergencies. Sleeping on a long
  ban catches a lot of heat-of-moment calls.

## Player-facing version

The `/rules` page derives from [`docs/community/rules.md`](../rules.md).
The `/appeals` page derives from this doc's Appeals section, but
omits the duration matrix details (players don't need the full
table; "bans range from short-term to permanent depending on severity
and history" is enough), emphasizes the appeals process, and uses
plainer, non-technical language.

Maintain the derivation in sync: when this doc updates, update the
player-facing page.

## Related

- [`docs/community/rules.md`](../rules.md) — the actual rule text
  this matrix enforces (player-facing at `/rules`)
- [expectations.md](./expectations.md) — admin conduct in general
- [incident-template.md](./incident-template.md) — writeup format
  for precedent-setting decisions
- Terms of Service (`/tos`) — the legal backstop for our authority
  to sanction
