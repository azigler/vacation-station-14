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
# Intended to be driven by vs14-postgres-retention.timer. Runs as the
# 'postgres' system user (peer auth via unix socket — no password).
#
# Knobs:
#   PG_DB                — database name (default: vacation_station)
#   CONNECTION_LOG_DAYS  — connection_log retention window (default: 30)
#   IPINTEL_CACHE_DAYS   — ipintel_cache retention window (default: 30)
#   PLAYER_INACTIVE_DAYS — player inactivity window (default: 365)

set -euo pipefail

PG_DB="${PG_DB:-vacation_station}"
CONNECTION_LOG_DAYS="${CONNECTION_LOG_DAYS:-30}"
IPINTEL_CACHE_DAYS="${IPINTEL_CACHE_DAYS:-30}"
PLAYER_INACTIVE_DAYS="${PLAYER_INACTIVE_DAYS:-365}"

echo ">>> Retention prune for ${PG_DB}"
echo "    connection_log:      keep ${CONNECTION_LOG_DAYS} days"
echo "    ipintel_cache:       keep ${IPINTEL_CACHE_DAYS} days"
echo "    player (inactive):   keep ${PLAYER_INACTIVE_DAYS} days (banned users excluded)"

# Use a single transaction so a partial failure doesn't leave the DB
# in a half-pruned state. RETURNING into a temp aggregate gives us
# row counts for the journal log without an extra query.
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

echo ">>> Retention prune complete."
