#!/bin/bash
# Vacation Station 14 — restore rehearsal
#
# An unrestored backup is not a backup, it is a file. This script is the proof
# step: it restores a dump into a THROWAWAY database, compares the row count of
# every public table against the live database, and drops the throwaway again.
#
# SAFETY. The live database is never a restore target. $SCRATCH_DB is asserted
# to differ from $PG_DB before anything runs, every psql/pg_restore invocation
# names its database explicitly, and the only DROP is of $SCRATCH_DB.
#
# OUTCOME CONTRACT. The last line is always
#
#     REHEARSAL_RESULT=<ok|mismatch|failed>
#
#   ok        every public table restored with an identical row count
#   mismatch  the restore ran but the data does not agree with live
#   failed    the restore itself did not complete
#
# Exit 0 on ok, 1 otherwise. Written for both GNU and BSD userland — this
# directory learned the hard way (see backup.sh's PORTABILITY note) that a
# script driven by a timer on two operating systems has to be portable or it
# is a silent nightly no-op.
#
# Usage:
#   ops/postgres/restore-rehearsal.sh                 # newest dump in BACKUP_DIR
#   ops/postgres/restore-rehearsal.sh path/to.dump    # a specific dump
#
# Knobs: PG_DB, BACKUP_DIR, SCRATCH_DB.
#
# A row-count comparison against live is the right check for a mostly-append
# database and the wrong one for a busy write path: rows legitimately written
# between the dump and the comparison show up as a mismatch. Compare with
# `DRIFT_TOLERANT=1` on a live server, which downgrades "restored <= live" to a
# note; the default is strict on purpose, because vs14 is tabled today.

set -uo pipefail

PG_DB="${PG_DB:-vacation_station}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/vacation-station}"
SCRATCH_DB="${SCRATCH_DB:-${PG_DB}_restoretest}"
DRIFT_TOLERANT="${DRIFT_TOLERANT:-0}"

VERDICT="failed"
finish() {
    rc=$?
    printf 'REHEARSAL_RESULT=%s\n' "${VERDICT}"
    [ "${VERDICT}" = "ok" ] && exit 0
    [ "${rc}" -eq 0 ] && rc=1
    exit "${rc}"
}
trap finish EXIT

if [ "${SCRATCH_DB}" = "${PG_DB}" ]; then
    echo "ABORT: SCRATCH_DB is the live database. Refusing." >&2
    exit 1
fi

DUMP="${1:-}"
if [ -z "${DUMP}" ]; then
    # Names carry a zero-padded UTC timestamp, so newest == last lexically.
    DUMP="$(find "${BACKUP_DIR}" -maxdepth 1 -type f -name "*-${PG_DB}-*.dump" |
        LC_ALL=C sort -r | head -1)"
fi
if [ -z "${DUMP}" ] || [ ! -f "${DUMP}" ]; then
    echo "ABORT: no dump to rehearse (looked in ${BACKUP_DIR})" >&2
    exit 1
fi

echo ">>> Rehearsing ${DUMP} ($(wc -c <"${DUMP}" | tr -d '[:space:]') bytes)"

if [ -f "${DUMP}.sha256" ] && [ -s "${DUMP}.sha256" ]; then
    echo "    checksum on file: $(awk '{print $1}' <"${DUMP}.sha256")"
else
    echo "    WARNING: no non-empty checksum beside this dump"
fi

echo ">>> Rebuilding scratch database ${SCRATCH_DB}"
dropdb --if-exists "${SCRATCH_DB}" || true
createdb "${SCRATCH_DB}" || {
    echo "ABORT: could not create ${SCRATCH_DB}" >&2
    exit 1
}

# Always drop the scratch database, whatever happens from here.
cleanup_scratch() { dropdb --if-exists "${SCRATCH_DB}" >/dev/null 2>&1 || true; }
trap 'cleanup_scratch; finish' EXIT

echo ">>> Restoring"
if ! pg_restore --no-owner --no-privileges --exit-on-error -d "${SCRATCH_DB}" "${DUMP}"; then
    echo "ABORT: pg_restore failed" >&2
    exit 1
fi

TABLE_SQL="SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename"
LIVE_TABLES="$(psql -d "${PG_DB}" -tAc "${TABLE_SQL}")"
REST_TABLES="$(psql -d "${SCRATCH_DB}" -tAc "${TABLE_SQL}")"

if [ "${LIVE_TABLES}" != "${REST_TABLES}" ]; then
    echo "!!! table LIST differs between live and restored" >&2
    VERDICT="mismatch"
    exit 1
fi

echo ">>> Comparing row counts across $(printf '%s\n' "${LIVE_TABLES}" | wc -l | tr -d ' ') public tables"
printf '    %-28s %10s %10s\n' TABLE LIVE RESTORED
BAD=0
NONEMPTY=0
for t in ${LIVE_TABLES}; do
    l="$(psql -d "${PG_DB}" -tAc "SELECT count(*) FROM public.\"${t}\"")"
    r="$(psql -d "${SCRATCH_DB}" -tAc "SELECT count(*) FROM public.\"${t}\"")"
    flag=""
    if [ "${l}" != "${r}" ]; then
        if [ "${DRIFT_TOLERANT}" = "1" ] && [ "${r}" -le "${l}" ]; then
            flag="  (drift, tolerated)"
        else
            flag="  <<< MISMATCH"
            BAD=$((BAD + 1))
        fi
    fi
    [ "${r}" -gt 0 ] && NONEMPTY=$((NONEMPTY + 1))
    printf '    %-28s %10s %10s%s\n' "${t}" "${l}" "${r}" "${flag}"
done

echo ">>> ${NONEMPTY} restored tables hold data; ${BAD} row-count mismatches"

# A restore that produces 40 empty tables also "matches" an empty live DB. Make
# the rehearsal refuse to call that a pass.
if [ "${NONEMPTY}" -eq 0 ]; then
    echo "!!! nothing was restored — every table is empty" >&2
    VERDICT="mismatch"
    exit 1
fi

if [ "${BAD}" -ne 0 ]; then
    VERDICT="mismatch"
    exit 1
fi

VERDICT="ok"
echo ">>> Rehearsal passed. Dropping ${SCRATCH_DB}."
