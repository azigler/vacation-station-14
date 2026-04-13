#!/usr/bin/env bash
# Vacation Station 14 — guidebook static-site build (vs-1e5)
#
# Renders the in-game Guidebook (Resources/ServerInfo/Guidebook/*.xml +
# Resources/Prototypes/Guidebook/*.yml) into a static HTML site and
# rsyncs it into /var/www/vs14-guidebook/ for nginx to serve at
# https://ss14.zig.computer/guidebook/.
#
# Idempotent; safe to re-run. Driven by vs14-guidebook-build.timer
# (daily, 05:15 UTC). Manual:
#     sudo systemctl start vs14-guidebook-build.service
#
# Env knobs (all optional; defaults mirror the systemd unit):
#   REPO_ROOT                 deploy checkout root
#                             (default: /opt/vacation-station)
#   GUIDEBOOK_SOURCE_DIR      read-only VS14 clone the renderer parses
#                             (default: /var/lib/vs14-guidebook-source)
#   GUIDEBOOK_SOURCE_URL      remote the sibling tracks
#                             (default: https://github.com/azigler/vacation-station-14)
#   GUIDEBOOK_SOURCE_BRANCH   branch the sibling tracks
#                             (default: main)
#   WEB_ROOT                  nginx alias target
#                             (default: /var/www/vs14-guidebook)

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vacation-station}"
GUIDEBOOK_SOURCE_DIR="${GUIDEBOOK_SOURCE_DIR:-/var/lib/vs14-guidebook-source}"
GUIDEBOOK_SOURCE_URL="${GUIDEBOOK_SOURCE_URL:-https://github.com/azigler/vacation-station-14}"
GUIDEBOOK_SOURCE_BRANCH="${GUIDEBOOK_SOURCE_BRANCH:-main}"
WEB_ROOT="${WEB_ROOT:-/var/www/vs14-guidebook}"

OPS_DIR="${REPO_ROOT}/ops/guidebook"
RENDER_SCRIPT="${OPS_DIR}/render.py"

log() { printf '[guidebook] %s\n' "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

[ -x "${RENDER_SCRIPT}" ] || [ -f "${RENDER_SCRIPT}" ] \
    || die "render.py missing at ${RENDER_SCRIPT}"

# Pillow is optional but required for directional sprite slicing (vs-mlg).
# If absent, render.py still builds — directional entity embeds fall back
# to text pills and a warning is logged. Non-directional sprites still
# render fine via plain file copy.
if ! python3 -c 'from PIL import Image' 2>/dev/null; then
    log "WARN: Pillow (python3-pil) not installed — directional entity sprites"
    log "      will fall back to text pills. Install via: apt install python3-pil"
fi

# --- 1. Sibling source clone ---
# The renderer only reads Resources/; a dedicated clone keeps the live
# dev/deploy tree untouched and is cheap to `git reset --hard`.

if [ ! -d "${GUIDEBOOK_SOURCE_DIR}/.git" ]; then
    log "cloning VS14 source mirror into ${GUIDEBOOK_SOURCE_DIR}"
    mkdir -p "$(dirname "${GUIDEBOOK_SOURCE_DIR}")"
    git clone --branch "${GUIDEBOOK_SOURCE_BRANCH}" \
        "${GUIDEBOOK_SOURCE_URL}" "${GUIDEBOOK_SOURCE_DIR}"
else
    log "updating VS14 source mirror at ${GUIDEBOOK_SOURCE_DIR}"
    git -c safe.directory='*' -C "${GUIDEBOOK_SOURCE_DIR}" fetch --prune origin
    git -c safe.directory='*' -C "${GUIDEBOOK_SOURCE_DIR}" reset \
        --hard "origin/${GUIDEBOOK_SOURCE_BRANCH}"
    git -c safe.directory='*' -C "${GUIDEBOOK_SOURCE_DIR}" clean -fdx
fi

# --- 2. Render into a scratch dir, then atomically publish ---

STAGE_DIR="$(mktemp -d -t vs14-guidebook-XXXXXX)"
trap 'rm -rf "${STAGE_DIR}"' EXIT

log "rendering into ${STAGE_DIR}"
python3 "${RENDER_SCRIPT}" --repo "${GUIDEBOOK_SOURCE_DIR}" --out "${STAGE_DIR}"

# Sanity check — must have an index and a reasonable number of pages.
[ -f "${STAGE_DIR}/index.html" ] || die "render produced no index.html"
page_count=$(find "${STAGE_DIR}" -maxdepth 1 -name '*.html' | wc -l)
[ "${page_count}" -ge 10 ] || die "render produced only ${page_count} page(s) — aborting publish"

log "publishing ${page_count} page(s) to ${WEB_ROOT}"
mkdir -p "${WEB_ROOT}"
rsync -a --delete "${STAGE_DIR}/" "${WEB_ROOT}/"

log "done."
