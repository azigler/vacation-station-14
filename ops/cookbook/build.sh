#!/bin/bash
# Vacation Station 14 — ss14-cookbook build + deploy
#
# Drives the vanilla arimah/ss14-cookbook (vendored as a submodule at
# external/cookbook) against a sibling read-only VS14 clone, then
# rsyncs the static output into nginx's alias target at
# /var/www/vs14-recipes/ (see ops/nginx/ss14.zig.computer.conf).
#
# Idempotent: safe to re-run. Driven by vs14-cookbook-build.timer
# (daily) or by hand:
#     sudo systemctl start vs14-cookbook-build.service
#
# Runs as the `ss14` system user (same account as the watchdog).
# Writes are confined to the ReadWritePaths declared in the unit
# file; any write outside those two roots will EPERM.
#
# Env knobs (all optional; defaults below mirror the service unit):
#   REPO_ROOT              path to the VS14 deploy checkout
#                          (default: /opt/vacation-station)
#   COOKBOOK_SOURCE_DIR    sibling clone the cookbook parses
#                          (default: /var/lib/vs14-cookbook-source)
#   COOKBOOK_SOURCE_URL    remote the sibling tracks
#                          (default: https://github.com/azigler/vacation-station-14)
#   COOKBOOK_SOURCE_BRANCH branch the sibling tracks
#                          (default: main)
#   WEB_ROOT               final served dir (nginx alias target)
#                          (default: /var/www/vs14-recipes)
#   COOKBOOK_BASE_PATH     URL path prefix baked into asset links
#                          (default: /recipes)
#   COOKBOOK_REPO_URL      "View source" link in cookbook footer —
#                          AGPLv3 compliance hook
#                          (default: https://github.com/azigler/vacation-station-14)

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vacation-station}"
COOKBOOK_SOURCE_DIR="${COOKBOOK_SOURCE_DIR:-/var/lib/vs14-cookbook-source}"
COOKBOOK_SOURCE_URL="${COOKBOOK_SOURCE_URL:-https://github.com/azigler/vacation-station-14}"
COOKBOOK_SOURCE_BRANCH="${COOKBOOK_SOURCE_BRANCH:-main}"
WEB_ROOT="${WEB_ROOT:-/var/www/vs14-recipes}"
COOKBOOK_BASE_PATH="${COOKBOOK_BASE_PATH:-/recipes}"
COOKBOOK_REPO_URL="${COOKBOOK_REPO_URL:-https://github.com/azigler/vacation-station-14}"

COOKBOOK_DIR="${REPO_ROOT}/external/cookbook"
OPS_DIR="${REPO_ROOT}/ops/cookbook"

log() { printf '>>> %s\n' "$*"; }

# --- 1. Sibling VS14 clone ---
# The cookbook reads raw YAML + PNG files from Resources/. We keep a
# dedicated read-only clone separate from the deploy checkout so it
# can be `git clean`ed / resynced without touching a live dev tree.

if [ ! -d "${COOKBOOK_SOURCE_DIR}/.git" ]; then
    log "cloning VS14 source mirror into ${COOKBOOK_SOURCE_DIR}"
    mkdir -p "$(dirname "${COOKBOOK_SOURCE_DIR}")"
    git clone --branch "${COOKBOOK_SOURCE_BRANCH}" \
        "${COOKBOOK_SOURCE_URL}" "${COOKBOOK_SOURCE_DIR}"
else
    log "updating VS14 source mirror at ${COOKBOOK_SOURCE_DIR}"
    git -C "${COOKBOOK_SOURCE_DIR}" fetch --prune origin
    git -C "${COOKBOOK_SOURCE_DIR}" reset --hard "origin/${COOKBOOK_SOURCE_BRANCH}"
    git -C "${COOKBOOK_SOURCE_DIR}" clean -fdx
fi

# Cookbook only needs Resources/; no submodules, no dotnet, no RUN_THIS.py.

# --- 2. Stage VS14 config into the cookbook checkout ---
# The cookbook npm scripts resolve paths relative to the cookbook's
# cwd, so we copy our VS14-specific inputs into external/cookbook/.
# These files are gitignored upstream (sources.yml, privacy.html,
# rewrites_vacation.yml) or match upstream's naming; overwriting is
# safe and idempotent.

log "staging VS14 cookbook config into ${COOKBOOK_DIR}"
install -m0644 "${OPS_DIR}/sources.yml"           "${COOKBOOK_DIR}/sources.yml"
install -m0644 "${OPS_DIR}/privacy.html"          "${COOKBOOK_DIR}/privacy.html"
install -m0644 "${OPS_DIR}/rewrites_vacation.yml" "${COOKBOOK_DIR}/rewrites_vacation.yml"

# --- 3. Write the .env the cookbook build reads ---
# env-cmd loads this before rollup runs. Keys documented in
# external/cookbook/.env.example. COOKBOOK_REPO_URL is the AGPLv3
# "View source" hook — the cookbook footer links to this URL.

log "writing cookbook .env (base path=${COOKBOOK_BASE_PATH}, repo=${COOKBOOK_REPO_URL})"
cat > "${COOKBOOK_DIR}/.env" <<EOF
COOKBOOK_BASE_PATH=${COOKBOOK_BASE_PATH}
COOKBOOK_REPO_URL=${COOKBOOK_REPO_URL}
COOKBOOK_TRUSTED_HOSTS=
COOKBOOK_CANONICAL_URL=https://ss14.zig.computer${COOKBOOK_BASE_PATH}
EOF

# --- 4. npm ci + build + recipe gen ---
# `npm ci` is deterministic and much faster than `npm install` on
# repeat runs when package-lock.json hasn't changed (node_modules
# cache across runs — systemd unit doesn't wipe the cookbook dir).

cd "${COOKBOOK_DIR}"

log "npm ci"
npm ci --no-audit --no-fund

log "npm run build"
npm run build

log "npm run gen:recipes"
npm run gen:recipes

# --- 5. Publish static output to nginx alias target ---
# `public/` is the cookbook's publishable directory. rsync with
# --delete keeps the served tree in lockstep with the fresh build.
# We specifically do NOT --delete the cookbook's data/ sub-tree
# inside public/ mid-build (gen:recipes retains old recipe data on
# purpose for long-lived browser tabs, per upstream README).

if [ ! -d "${COOKBOOK_DIR}/public" ]; then
    echo "ERROR: ${COOKBOOK_DIR}/public missing after build" >&2
    exit 1
fi

log "publishing to ${WEB_ROOT}"
mkdir -p "${WEB_ROOT}"
rsync -a --delete "${COOKBOOK_DIR}/public/" "${WEB_ROOT}/"

log "done."
