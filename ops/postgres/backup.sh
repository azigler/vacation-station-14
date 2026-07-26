#!/bin/bash
# Vacation Station 14 — nightly PostgreSQL backup
#
# Writes a timestamped pg_dump (custom format, compressed) to $BACKUP_DIR,
# proves the archive is readable, checksums it, then prunes old dumps per the
# retention policy: keep the last 7 daily dumps + the last 4 weekly (Sunday)
# dumps.
#
# TWO HOSTS, TWO USERLANDS. This script is driven by the systemd timer units
# beside it on Linux and by launchd on pico (the macOS application host — see
# com.zig.ss14-backup.plist in this directory). Both reach it through the
# /opt/vacation-station symlink, which is why the path is host-portable. The
# script itself was not.
#
# THE BUG THIS FILE IS THE FIX FOR (vs14d-jms, 2026-07-26). Two GNU-only
# commands made every macOS run exit 127:
#
#   * sha256sum    — GNU coreutils. macOS ships `shasum`; coreutils is not
#                    installed on pico. `set -euo pipefail` then aborted the
#                    script at that line, which is AFTER the dump and BEFORE
#                    the prune. So the dumps were real, every .dump.sha256 was
#                    0 bytes, and retention never ran once in two months.
#   * find -printf — GNU findutils. BSD find: "unknown primary or operator".
#                    Latent, because line 36 always died first.
#
# Neither is used now. Dump names embed a zero-padded UTC timestamp, so a
# byte-wise sort IS a chronological sort; mtime — and therefore -printf '%T@' —
# is not needed, and is in fact the worse key, since any copy or restore of the
# backup directory rewrites mtimes while the names stay true.
#
# OUTCOME CONTRACT. The last line of every run, including a crash, is
#
#     BACKUP_RESULT=<ok|failed>
#
# and the same verdict is mirrored three ways inside $BACKUP_DIR:
#
#     STATUS.json          last run, overwritten
#     backup-ledger.jsonl  append-only history, one JSON object per run
#     BACKUP-FAILING       written on a non-ok verdict, removed by the next ok
#
# The real defect here was never the PATH — it was that a nightly job failed
# for two months and the only witness was the exit-code column of
# `launchctl list`, which nobody reads. bin/backup-health.sh in ~/vs14d is the
# fail-closed consumer of the contract above: it treats a missing, stale or
# unparseable status as FAILED, never as silence. An exit code nobody reads is
# not a report.
#
# Knobs:
#   PG_DB           database name           (default: vacation_station)
#   BACKUP_DIR      output directory        (default: /var/backups/vacation-station)
#   DAILY_KEEP      daily dumps to keep     (default: 7)
#   WEEKLY_KEEP     weekly dumps to keep    (default: 4)
#   MIN_DUMP_BYTES  floor for a sane dump   (default: 4096) — a 0-byte dump is
#                   a failure, not a backup

set -euo pipefail

PG_DB="${PG_DB:-vacation_station}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/vacation-station}"
DAILY_KEEP="${DAILY_KEEP:-7}"
WEEKLY_KEEP="${WEEKLY_KEEP:-4}"
MIN_DUMP_BYTES="${MIN_DUMP_BYTES:-4096}"

STATUS_JSON="${BACKUP_DIR}/STATUS.json"
LEDGER="${BACKUP_DIR}/backup-ledger.jsonl"
SENTINEL="${BACKUP_DIR}/BACKUP-FAILING"

# Pessimistic defaults: every terminal path that is not an explicit success
# reports failure, so a crash between here and the end cannot read as silence.
VERDICT="failed"
DETAIL="aborted before reaching a terminal path"
OUT=""
BYTES=0

finish() {
    local rc=$?

    if [ "${rc}" -ne 0 ] && [ "${VERDICT}" = "ok" ]; then
        # Something after the success point still blew up. Success is retracted.
        VERDICT="failed"
        DETAIL="exit ${rc} after the dump was accepted"
    fi

    # Keep the JSON valid whatever ended up in DETAIL.
    DETAIL="${DETAIL//\"/\'}"
    DETAIL="${DETAIL//$'\n'/ }"

    local ts line
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    line="$(printf '{"ts":"%s","host":"%s","job":"ss14-backup","db":"%s","verdict":"%s","dump":"%s","bytes":%s,"exit":%s,"detail":"%s"}' \
        "${ts}" "$(hostname -s)" "${PG_DB}" "${VERDICT}" "${OUT}" "${BYTES}" "${rc}" "${DETAIL}")"

    if [ -d "${BACKUP_DIR}" ]; then
        printf '%s\n' "${line}" >"${STATUS_JSON}" || true
        printf '%s\n' "${line}" >>"${LEDGER}" || true
        if [ "${VERDICT}" = "ok" ]; then
            rm -f "${SENTINEL}" || true
        else
            printf '%s\n' "${line}" >"${SENTINEL}" || true
        fi
    fi

    printf 'BACKUP_RESULT=%s\n' "${VERDICT}"
    exit "${rc}"
}
trap finish EXIT

# Portable SHA-256. GNU coreutils, then the BSD/macOS spelling, then openssl.
# All three print "<hex>  <path>"-shaped output; the point is a checksum that
# EXISTS, not one byte-identical across platforms.
sha256_into() { # $1 = file to hash, $2 = destination
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" >"$2"
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" >"$2"
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 -r "$1" >"$2"
    else
        return 1
    fi
}

prune() {
    local prefix="$1" keep="$2" old
    find "${BACKUP_DIR}" -maxdepth 1 -type f -name "${prefix}-${PG_DB}-*.dump" |
        LC_ALL=C sort -r |
        awk -v keep="${keep}" 'NR>keep' |
        while IFS= read -r old; do
            echo "    pruning $(basename "${old}")"
            rm -f "${old}" "${old}.sha256"
        done
}

DETAIL="could not create ${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}"

# Weekly dumps taken on Sundays get a distinct prefix so retention can prune
# daily and weekly cohorts independently.
if [ "$(date +%u)" = "7" ]; then
    PREFIX="weekly"
else
    PREFIX="daily"
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${BACKUP_DIR}/${PREFIX}-${PG_DB}-${TS}.dump"

DETAIL="pg_dump failed"
echo ">>> Dumping ${PG_DB} -> ${OUT}"
pg_dump -Fc --no-owner --no-privileges -d "${PG_DB}" -f "${OUT}"

# `wc -c` rather than stat(1), whose flags differ between GNU and BSD — the
# exact class of mistake that produced this file.
BYTES="$(wc -c <"${OUT}" | tr -d '[:space:]')"
if [ "${BYTES}" -lt "${MIN_DUMP_BYTES}" ]; then
    DETAIL="dump is ${BYTES} bytes, under the ${MIN_DUMP_BYTES}-byte floor"
    echo "!!! ${DETAIL}" >&2
    exit 1
fi

# An unreadable archive is a file, not a backup. pg_restore -l parses the whole
# table of contents, so a truncated or corrupt dump is caught here for a few
# milliseconds rather than during an outage.
DETAIL="pg_restore -l could not read ${OUT}"
echo ">>> Verifying archive is readable"
pg_restore -l "${OUT}" >/dev/null

DETAIL="no sha256sum, shasum or openssl available for the checksum"
sha256_into "${OUT}" "${OUT}.sha256"

DETAIL="retention prune failed"
prune daily "${DAILY_KEEP}"
prune weekly "${WEEKLY_KEEP}"

VERDICT="ok"
DETAIL="${BYTES} bytes, archive readable, checksum written"
echo ">>> Backup complete: ${OUT} (${BYTES} bytes)"
