#!/bin/bash
# Vacation Station 14 — replay rotation + metadata extraction
#
# Replays live at <instance>/data/replays/<year>/<month>/... per the
# auto_record_name in config.toml. This script:
#
#   1. Extracts tiny metadata sidecars (replay_final.yml) from each raw
#      zip older than RAW_KEEP_DAYS, alongside the zip.
#   2. Deletes raw zips older than RAW_KEEP_DAYS (keeping the sidecar).
#   3. Deletes sidecars older than METADATA_KEEP_DAYS.
#
# Runs as the 'ss14' user via the ss14-replay-rotate.service systemd unit.

set -euo pipefail

REPLAY_ROOT="${REPLAY_ROOT:-/opt/ss14-watchdog/instances/vacation-station/data/replays}"
RAW_KEEP_DAYS="${RAW_KEEP_DAYS:-14}"
METADATA_KEEP_DAYS="${METADATA_KEEP_DAYS:-180}"

if [ ! -d "${REPLAY_ROOT}" ]; then
    echo ">>> No replay root at ${REPLAY_ROOT}; nothing to do."
    exit 0
fi

echo ">>> Rotating replays at ${REPLAY_ROOT}"
echo "    raw keep: ${RAW_KEEP_DAYS} days"
echo "    metadata keep: ${METADATA_KEEP_DAYS} days"

# --- Step 1: extract metadata sidecars for zips older than RAW_KEEP_DAYS ---

extracted=0
find "${REPLAY_ROOT}" -type f -name '*.zip' -mtime "+${RAW_KEEP_DAYS}" \
    | while IFS= read -r zip; do
        sidecar="${zip%.zip}.meta.yml"
        if [ -f "${sidecar}" ]; then
            continue
        fi
        if unzip -p "${zip}" replay_final.yml > "${sidecar}" 2>/dev/null; then
            extracted=$((extracted + 1))
        else
            # Older engine builds used replay_meta.yml; try that name too.
            if unzip -p "${zip}" replay_meta.yml > "${sidecar}" 2>/dev/null; then
                extracted=$((extracted + 1))
            else
                rm -f "${sidecar}"
                echo "    WARN: no replay_final.yml or replay_meta.yml in ${zip}"
            fi
        fi
    done

echo "    extracted sidecars (approx): ${extracted}"

# --- Step 2: delete raw zips older than RAW_KEEP_DAYS ---

deleted_raw=0
find "${REPLAY_ROOT}" -type f -name '*.zip' -mtime "+${RAW_KEEP_DAYS}" \
    | while IFS= read -r zip; do
        rm -f "${zip}"
        deleted_raw=$((deleted_raw + 1))
    done

echo "    deleted raw zips: ${deleted_raw}"

# --- Step 3: delete metadata sidecars older than METADATA_KEEP_DAYS ---

deleted_meta=0
find "${REPLAY_ROOT}" -type f -name '*.meta.yml' -mtime "+${METADATA_KEEP_DAYS}" \
    | while IFS= read -r sidecar; do
        rm -f "${sidecar}"
        deleted_meta=$((deleted_meta + 1))
    done

echo "    deleted metadata sidecars: ${deleted_meta}"

# --- Step 4: prune now-empty month / year dirs ---

find "${REPLAY_ROOT}" -mindepth 2 -type d -empty -delete 2>/dev/null || true

# --- Summary ---

total_zips=$(find "${REPLAY_ROOT}" -type f -name '*.zip' 2>/dev/null | wc -l)
total_meta=$(find "${REPLAY_ROOT}" -type f -name '*.meta.yml' 2>/dev/null | wc -l)
disk_used=$(du -sh "${REPLAY_ROOT}" 2>/dev/null | awk '{print $1}')

echo ">>> Rotation complete."
echo "    remaining raw zips: ${total_zips}"
echo "    remaining metadata sidecars: ${total_meta}"
echo "    replay tree size: ${disk_used:-unknown}"
