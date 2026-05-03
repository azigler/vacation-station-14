# Vacation Station 14 — Data Retention Policy

**Last updated: 2026-05-02**

This document specifies how long the Service retains each category
of data, why, and how it is deleted at the end of its retention
window. The [privacy policy](./privacy.md) summarizes this; this
document is the source of truth.

The Service is operated by **azigler** ("the operator"). Contact:
`legal@zig.computer`.

## Retention schedule

| Data | Retention | Purpose | Deletion mechanism | Storage |
|---|---|---|---|---|
| Hub username (player record) | Up to 1 year after last activity | Continuity for returning players | Database prune query | Database |
| Discord ID and username | Indefinite while member | Identify and route Discord users | Manual on leave or DSAR | Database |
| IP address (connection) | 30 days | Ban-evasion detection; abuse mitigation | Log rotation | System logs |
| IP intelligence cache | 30 days | Cached VPN / proxy verdicts to avoid re-querying upstream services | Database prune cron | Database |
| Ahelp transcripts (admin-player chat) | Indefinite | Moderation audit trail; appeals review | Manual only | Database |
| Round replays (raw) | 14 days | Round reconstruction; moderation; debug | Filesystem cron | Watchdog instance data directory |
| Round replays (metadata) | 180 days | Statistics | Filesystem cron | Same as raw; metadata-only after raw deletion |
| Admin actions (bans, warns, role changes) | Indefinite | Legal record of moderation decisions; ban appeals | Manual only | Database |
| Connection events (join/leave/duration) | 30 days | Statistics; abuse pattern detection | Database prune cron | Database |
| Server logs (Loki) | 30 days | Diagnose crashes and performance | Loki retention rule | Loki ingestion |
| Server logs (journald) | 30 days | Diagnose crashes and performance | Journald rotation | System journal |
| Watchdog file logs | 30 days | Service supervision and crash analysis | Logrotate | Watchdog log directory |
| Database backups | 28 days | Disaster recovery | Backup timer rotation | Backup directory |
| Website request logs | 14 days | Abuse mitigation; debugging | Logrotate | Webserver log directory |
| Incident reports (security events) | 1 year | Audit; cross-incident pattern detection | Manual archive | Maintainer-held archive |

In-game IC and OOC chat are captured in round replays — see the
replay rows above. Replay retention governs that data; there is no
separate chat-log table.

The Service does not maintain a local cache of Discord messages.
Discord stores all messages on their infrastructure per Discord's
own privacy policy.

The numbers in this table are maximum retention. Data is deleted at
the end of its window without exception, subject to the policies
below.

## Definitions

- **Account active**: a player account is considered active if its
  `last_seen` timestamp is within the past 1 year. Beyond 1 year
  of inactivity, the player record is pruned. Ban records are
  preserved separately under the permanent-identifier policy
  regardless of activity.

## Permanent identifier retention (ban evasion)

When a user is banned, specific identifiers are retained
indefinitely on the ban record:

- Hub username (and any aliases known)
- IP address at time of ban
- Discord ID (if the ban applies to Discord)
- Date and reason of ban
- Any subsequent IPs flagged for evasion

These identifiers are retained even if the user later requests
data deletion. The ban itself is a legal record — it justifies the
operator's right to refuse service and is the basis of any future
appeal — and ban-evasion detection requires the identifiers be
checkable against new connections.

Right-of-erasure requests preserve the ban record as a "tombstone"
with minimal personal data (the identifiers above) but delete
ancillary content: chat from outside the ban event, replays from
unrelated rounds, and non-ban connection records.

## Deletion on user request (DSAR)

When a user exercises the right to data deletion under GDPR / CCPA:

1. **Game data** — username and player record marked for deletion
   on the next nightly prune. Active sessions terminated. Chat
   logs, replays, and connection records associated with that user
   are deleted out-of-cycle within 7 days.
2. **Discord data** — Discord ID and username are deleted from
   the Service's database. Discord messages and account data are
   stored on Discord's infrastructure, not the Service; deletion
   of those records must be requested from Discord directly per
   their privacy policy.
3. **Backups** — database backups are not selectively edited.
   User-marked-for-deletion records roll out of backups as the
   28-day window passes; this is an acceptable delay under GDPR's
   "without undue delay" standard.
4. **Admin / ban records** — preserved per the permanent-identifier
   policy above. The user is notified that this exception applies.

A DSAR is acknowledged within 30 days; substantive deletion
typically completes within 7 days plus the backup-rollover window
(another 28 days for full purge).

## Backups

Database backups are written daily by a backup timer service to a
backup directory on the server. The timer rotates the backup set:
daily backups for 7 days, weekly backups for 4 weeks, oldest
dropped at 28 days. No off-site backups are taken routinely; the
operator may take a manual encrypted snapshot before destructive
infrastructure changes (e.g., before a major schema migration) and
hold it for the duration of the change window only.

## Logs

| Log source | Retention | Mechanism |
|---|---|---|
| Systemd journal (all units) | 30 days | Journald retention setting |
| Webserver access + error | 14 days | Logrotate |
| Watchdog file logs | 30 days | Logrotate |
| Loki ingestion | 30 days | Loki retention rule |

Log retention is the same regardless of log content. Personal
identifiers in logs (IP addresses, usernames) are retained for the
same window as the operational log itself.

## Incident retention

When a security incident occurs (brute-force attack, exploit
attempt, doxxing report, hub-mod escalation, for-cause admin
removal, data-privacy event), the operator writes an incident
report per [incident-template.md](../admin/incident-template.md)
and retains it for at least 1 year. After 1 year, the report may
be archived to long-term storage or deleted at the operator's
discretion based on its continuing relevance.

Incident reports may contain user data (handles, IPs, chat
excerpts) by necessity. They are not subject to right-of-erasure
requests during the 1-year retention window if the user is the
subject of the incident, because the report is the legal record of
the operator's response.

## Changes to this policy

This policy may be updated as the Service evolves. Material
changes (new data categories, longer retention windows, changed
deletion mechanisms) will be announced on the website and in the
Discord. The "Last updated" date at the top reflects the most
recent change.

## Contact

Retention questions: `legal@zig.computer`.
