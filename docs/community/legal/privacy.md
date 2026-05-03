# Vacation Station 14 — Privacy Policy

**Last updated: 2026-05-02**

This privacy policy describes what data the Vacation Station 14
service ("the Service") collects, why it is collected, how long it
is kept, and what rights you have over your data. It applies to the
game server, the Discord server, and the website at
ss14.zig.computer.

The Service is operated by **azigler** ("the operator") as a
personal, non-commercial project. Contact for any privacy concern:
`legal@zig.computer`.

## Summary

In short:

- The Service collects only what is necessary to run a multiplayer
  game server and the surrounding community surfaces.
- No data is sold. No data is shared with advertisers or marketing
  partners. There are no third-party analytics on the website.
- Account-related data is retained while you participate, plus a
  reasonable window after, primarily for moderation and ban-history
  purposes.
- You can request access, correction, or deletion of your data at
  any time via `legal@zig.computer`.

## What we collect

### Account identifiers

| Data | Source | Why | Retention |
|---|---|---|---|
| Hub username | SS14 launcher (Wizards' Den OAuth) or guest | Identify you in-game; gate moderation actions | Up to 1 year after last activity |
| Discord ID and username | Discord (when you join our Discord) | Identify you in Discord; sync with in-game role | Indefinite while member; deleted on request |
| IP address | Game-server connection / website request | Ban-evasion detection; abuse mitigation | 30 days |
| IP intelligence cache | Upstream IP-intel service (queried on connection) | Detect VPN / proxy connections without re-querying upstream every time | 30 days |

### Activity data

| Data | Source | Why | Retention |
|---|---|---|---|
| In-game chat (IC, OOC) | Game server | Captured inside round replays | Governed by replay retention (see below) |
| Ahelp transcripts (admin-player chat) | Game server | Moderation audit trail; appeals review | Indefinite |
| Round replays | Game server | Round reconstruction; moderation; bug debugging | 14 days raw / 180 days metadata |
| Connection events (join, leave, time on server) | Game server | Statistics; abuse pattern detection | 30 days |
| Admin actions (bans, warns, role changes) | Game server / Discord | Legal record of moderation decisions; ban appeals | Indefinite |
| Discord messages | Discord | Read on demand via the Discord API | Stored only by Discord per their privacy policy; the Service does not maintain a local cache |

### Operational data

| Data | Source | Why | Retention |
|---|---|---|---|
| Server logs (errors, performance) | All services | Diagnose crashes and performance issues | 30 days |
| Database backups | Postgres | Disaster recovery | 28 days |
| Website request logs (nginx) | Website | Abuse mitigation; debugging | 14 days |

The full retention specification lives in the
[retention policy](./retention.md). Where the two documents differ,
the retention policy controls.

## Third parties

The Service uses these third parties; their own privacy policies
apply to the data each receives:

- **Wizards' Den** (https://central.spacestation14.io/) — provides
  hub authentication. They see your hub username and game-server
  pings.
- **Discord** — runs the Discord platform and stores all Discord
  data on their infrastructure. The Service's bots and admins see
  what Discord shows them.
- **OVHcloud** — provides the VPS that runs the game server,
  watchdog, database, and observability stack. They have technical
  access (root, hypervisor) but do not access user data outside
  legal compulsion.

The Service does not use analytics services, advertising networks,
or marketing tools.

## Cookies

The Service uses only essential cookies — those required for
functionality (e.g., website admin login, if applicable). There are
no analytics, tracking, or advertising cookies. No cookie banner is
required because no non-essential cookies are set.

## Your rights

Under California privacy law (CCPA/CPRA) and EU GDPR, you have:

- **Right of access** — request a copy of the data we hold about
  you
- **Right of rectification** — request correction of inaccurate
  data
- **Right of erasure** — request deletion of your data
- **Right to data portability** — receive your data in a
  machine-readable format
- **Right to object** — opt out of certain processing

To exercise any of these rights, email `legal@zig.computer` with:

- The right you wish to exercise
- Your username (game and / or Discord) so we can identify you
- A way to verify the request is yours (signed message in Discord,
  comment on a known issue, etc.)

We respond within 30 days.

### Caveats on deletion

- **Admin records** (bans, warns, sanction history, ahelp
  transcripts) are retained even after a deletion request, because
  they form the legal record of moderation decisions and the basis
  of any ban appeal. Your username is preserved in those records;
  ancillary content (in-game chat captured in replays, replays from
  unrelated rounds) is deleted.
- **Discord data** is stored on Discord's infrastructure, not on
  the Service. To delete Discord data, request deletion from
  Discord directly per their privacy policy. Your Discord ID and
  username in our database are deleted on DSAR request.

## Children

The Service is not directed to children under 16. We do not
knowingly collect data from anyone under 16. If you believe a child
under 16 has provided data, contact `legal@zig.computer` and we
will delete it.

## Changes to this policy

This policy may be updated as the Service evolves. Material changes
will be announced on the website and in the Discord. The "Last
updated" date at the top reflects the most recent change.

## Contact

Privacy concerns or requests: `legal@zig.computer`.
