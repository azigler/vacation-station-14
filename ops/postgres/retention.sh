#!/bin/bash
# Vacation Station 14 — nightly PostgreSQL retention prune
#
# Enforces docs/community/legal/retention.md commitments by deleting
# rows past their retention window from these tables:
#
#   1. connection_log     — older than 30 days (column: time)
#   2. ipintel_cache      — older than 30 days (column: time)
#   3. player             — last_seen_time older than 1 year, EXCLUDING
#                           any user_id present in ban_player (the
#                           permanent-identifier policy preserves ban
#                           records regardless of player activity)
#
# Tables intentionally NOT touched:
#   - admin_messages (ahelp transcripts)  — indefinite retention per policy
#   - admin_log                            — indefinite retention per policy
#   - ban / ban_player / ban_address /     — permanent identifiers
#     ban_hwid / ban_role / unban
#
# Driven by vs14-postgres-retention.timer on Linux and by launchd on pico (see
# com.zig.vs14-postgres-retention.plist in this directory), both through the
# /opt/vacation-station symlink. Unlike its sibling backup.sh it uses nothing
# but psql, so it survived the GNU-vs-BSD portability bug that broke backups
# for two months (vs14d-jms) — it has been exiting 0 nightly throughout.
#
# OUTCOME CONTRACT (added with vs14d-jms). The last line of every run,
# including a crash, is
#
#     RETENTION_RESULT=<ok|failed>
#
# mirrored into $STATE_DIR/retention-STATUS.json and appended to
# $STATE_DIR/retention-ledger.jsonl. This job was NOT broken; it gets the
# contract anyway, because "it exits 0 today" is not the same claim as "someone
# would notice if it stopped," and the second claim is the one that failed here.
#
# Knobs:
#   PG_DB                — database name (default: vacation_station)
#   CONNECTION_LOG_DAYS  — connection_log retention window (default: 30)
#   IPINTEL_CACHE_DAYS   — ipintel_cache retention window (default: 30)
#   PLAYER_INACTIVE_DAYS — player inactivity window (default: 365)
#   STATE_DIR            — where the verdict is recorded
#                          (default: /var/backups/vacation-station)

set -euo pipefail

PG_DB="${PG_DB:-vacation_station}"
CONNECTION_LOG_DAYS="${CONNECTION_LOG_DAYS:-30}"
IPINTEL_CACHE_DAYS="${IPINTEL_CACHE_DAYS:-30}"
PLAYER_INACTIVE_DAYS="${PLAYER_INACTIVE_DAYS:-365}"
STATE_DIR="${STATE_DIR:-/var/backups/vacation-station}"

VERDICT="failed"
DETAIL="aborted before reaching a terminal path"

finish() {
    local rc=$?
    if [ "${rc}" -ne 0 ] && [ "${VERDICT}" = "ok" ]; then
        VERDICT="failed"
        DETAIL="exit ${rc} after the prune was accepted"
    fi
    DETAIL="${DETAIL//\"/\'}"
    DETAIL="${DETAIL//$'\n'/ }"

    local ts line
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    line="$(printf '{"ts":"%s","host":"%s","job":"vs14-postgres-retention","db":"%s","verdict":"%s","exit":%s,"detail":"%s"}' \
        "${ts}" "$(hostname -s)" "${PG_DB}" "${VERDICT}" "${rc}" "${DETAIL}")"

    if [ -d "${STATE_DIR}" ]; then
        printf '%s\n' "${line}" >"${STATE_DIR}/retention-STATUS.json" || true
        printf '%s\n' "${line}" >>"${STATE_DIR}/retention-ledger.jsonl" || true
    fi

    printf 'RETENTION_RESULT=%s\n' "${VERDICT}"
    exit "${rc}"
}
trap finish EXIT

echo ">>> Retention prune for ${PG_DB}"
echo "    connection_log:      keep ${CONNECTION_LOG_DAYS} days"
echo "    ipintel_cache:       keep ${IPINTEL_CACHE_DAYS} days"
echo "    player (inactive):   keep ${PLAYER_INACTIVE_DAYS} days (banned users excluded)"

# Use a single transaction so a partial failure doesn't leave the DB
# in a half-pruned state. RETURNING into a temp aggregate gives us
# row counts for the journal log without an extra query.
DETAIL="psql prune transaction failed"
psql -d "${PG_DB}" --no-psqlrc --quiet --set ON_ERROR_STOP=1 <<SQL
\set CONNECTION_LOG_DAYS ${CONNECTION_LOG_DAYS}
\set IPINTEL_CACHE_DAYS ${IPINTEL_CACHE_DAYS}
\set PLAYER_INACTIVE_DAYS ${PLAYER_INACTIVE_DAYS}

BEGIN;

WITH pruned AS (
    DELETE FROM connection_log
    WHERE time < NOW() - make_interval(days => :CONNECTION_LOG_DAYS)
    RETURNING 1
)
SELECT 'connection_log: ' || COUNT(*) || ' rows pruned' AS result FROM pruned
\gset summary_

\echo :summary_result

WITH pruned AS (
    DELETE FROM ipintel_cache
    WHERE time < NOW() - make_interval(days => :IPINTEL_CACHE_DAYS)
    RETURNING 1
)
SELECT 'ipintel_cache:  ' || COUNT(*) || ' rows pruned' AS result FROM pruned
\gset summary_

\echo :summary_result

-- Player prune: inactive >1y AND not present in ban_player. The
-- ban-exclusion is critical to the permanent-identifier policy in
-- docs/community/legal/retention.md.
WITH pruned AS (
    DELETE FROM player
    WHERE last_seen_time < NOW() - make_interval(days => :PLAYER_INACTIVE_DAYS)
      AND user_id NOT IN (SELECT user_id FROM ban_player)
    RETURNING 1
)
SELECT 'player:         ' || COUNT(*) || ' rows pruned' AS result FROM pruned
\gset summary_

\echo :summary_result

COMMIT;
SQL

VERDICT="ok"
DETAIL="prune transaction committed"
echo ">>> Retention prune complete."
