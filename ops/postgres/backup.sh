#!/bin/bash
# Vacation Station 14 — nightly PostgreSQL backup
#
# Writes a timestamped pg_dump (custom format, compressed) to
# /var/backups/vacation-station/, then prunes old backups per the
# retention policy: keep the last 7 daily dumps + the last 4 weekly
# (Sunday) dumps.
#
# Intended to be driven by the systemd timer units in this directory.
# Runs as the 'postgres' system user (peer auth, no password needed).

set -euo pipefail

PG_DB="${PG_DB:-vacation_station}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/vacation-station}"
DAILY_KEEP="${DAILY_KEEP:-7}"
WEEKLY_KEEP="${WEEKLY_KEEP:-4}"

mkdir -p "${BACKUP_DIR}"

# Weekly dumps taken on Sundays get a distinct prefix so retention
# can prune daily and weekly cohorts independently.
if [ "$(date +%u)" = "7" ]; then
    PREFIX="weekly"
else
    PREFIX="daily"
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${BACKUP_DIR}/${PREFIX}-${PG_DB}-${TS}.dump"

echo ">>> Dumping ${PG_DB} -> ${OUT}"
pg_dump -Fc --no-owner --no-privileges -d "${PG_DB}" -f "${OUT}"

# Best-effort checksum for integrity tracking.
sha256sum "${OUT}" > "${OUT}.sha256"

# --- Retention ---

prune() {
    local prefix="$1"
    local keep="$2"
    # List matching dumps newest-first, drop the first $keep, rm the rest.
    # Use find -printf for stable parsing instead of ls.
    find "${BACKUP_DIR}" -maxdepth 1 -type f \
        -name "${prefix}-${PG_DB}-*.dump" \
        -printf '%T@ %p\n' \
        | sort -rn \
        | awk -v keep="${keep}" 'NR>keep {print $2}' \
        | while IFS= read -r old; do
            echo "    pruning $(basename "${old}")"
            rm -f "${old}" "${old}.sha256"
        done
}

prune daily  "${DAILY_KEEP}"
prune weekly "${WEEKLY_KEEP}"

echo ">>> Backup complete."
