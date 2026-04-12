#!/usr/bin/env bash
# Vacation Station 14 — SS14.MapViewer build + deploy pipeline (vs-236)
#
# End-to-end static-mode pipeline:
#
#   1. Render VS14 maps to PNG/WebP + a per-map map.json via
#      `Content.MapRenderer --viewer` (already in this repo).
#   2. Build SS14.MapViewer (the static frontend submodule at
#      external/mapviewer/) with its base path set to /maps/ so all
#      assets resolve correctly under the sub-path served by nginx.
#   3. Assemble the final bundle:
#        - MapViewer's Vite build output (index.html + JS/CSS + icons)
#        - our ops/mapviewer/config.json (points at relative maps/)
#        - the rendered tile PNGs/WebPs + map.json per map
#        - list.json enumerating maps for the selector
#   4. rsync atomically to /var/www/vs14-maps/ (served by nginx as
#      /maps/).
#
# Runs as the `ss14` user under a weekly systemd timer. Maps change
# infrequently so weekly cadence is plenty; manual force-rebuild is
# `sudo systemctl start vs14-mapviewer-build.service`.
#
# Idempotent: safe to re-run. Each stage writes to a staging dir
# first, then rsyncs to the serve root. No partial states are visible
# to the web if the build fails mid-way — rsync only runs after the
# earlier stages all succeed (`set -e`).
#
# Environment overrides (all optional):
#   VS14_ROOT         repo root (default: /opt/vacation-station)
#   MAPVIEWER_SRC     MapViewer submodule (default: $VS14_ROOT/external/mapviewer)
#   STAGE_DIR         scratch workspace (default: /var/cache/vs14-mapviewer)
#   SERVE_ROOT        nginx-served directory (default: /var/www/vs14-maps)
#   MAP_LIST          space-separated map IDs to render (default: auto-discover
#                     from Resources/Prototypes/Maps + _VS/Maps)
#   OUTPUT_FORMAT     png|webp (default: webp — smaller, MapViewer supports both)
#   SKIP_NPM_INSTALL  1 = skip `npm ci` (use existing node_modules)
#   SKIP_RENDER       1 = skip Content.MapRenderer invocation (reuse previous)
#
# Exit codes: 0 on success, non-zero on any stage failure.

set -euo pipefail

VS14_ROOT="${VS14_ROOT:-/opt/vacation-station}"
MAPVIEWER_SRC="${MAPVIEWER_SRC:-${VS14_ROOT}/external/mapviewer}"
STAGE_DIR="${STAGE_DIR:-/var/cache/vs14-mapviewer}"
SERVE_ROOT="${SERVE_ROOT:-/var/www/vs14-maps}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-webp}"

MAPRENDERER_PROJECT="${VS14_ROOT}/Content.MapRenderer/Content.MapRenderer.csproj"
OPS_CONFIG="${VS14_ROOT}/ops/mapviewer/config.json"

RENDER_OUT="${STAGE_DIR}/rendered-maps"
BUILD_OUT="${STAGE_DIR}/mapviewer-dist"
BUNDLE_OUT="${STAGE_DIR}/bundle"

log() { printf '[mapviewer-build] %s\n' "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

[ -d "${VS14_ROOT}" ]       || die "VS14_ROOT ${VS14_ROOT} not found"
[ -d "${MAPVIEWER_SRC}" ]   || die "MapViewer submodule not found at ${MAPVIEWER_SRC}; did you run 'git submodule update --init'?"
[ -f "${MAPRENDERER_PROJECT}" ] || die "Content.MapRenderer project not found at ${MAPRENDERER_PROJECT}"
[ -f "${OPS_CONFIG}" ]      || die "Missing ops config at ${OPS_CONFIG}"

mkdir -p "${STAGE_DIR}" "${RENDER_OUT}" "${BUILD_OUT}" "${BUNDLE_OUT}"

# ---------------------------------------------------------------------------
# Stage 1 — render maps
# ---------------------------------------------------------------------------
#
# Content.MapRenderer with --viewer emits both the image(s) and the
# map.json metadata MapViewer needs. Output layout is:
#
#   <RENDER_OUT>/<MapId>/<MapId>-0.(png|webp)
#   <RENDER_OUT>/<MapId>/map.json
#
# Auto-discover the map list by scanning prototype YAMLs under
# Resources/Prototypes/Maps + _VS/Maps, unless MAP_LIST was provided.

if [ -z "${MAP_LIST:-}" ]; then
    log "Auto-discovering maps from Resources/Prototypes/{Maps,_VS/Maps}"
    MAP_LIST="$(
        find "${VS14_ROOT}/Resources/Prototypes/Maps" \
             "${VS14_ROOT}/Resources/Prototypes/_VS/Maps" \
            -maxdepth 2 -type f -name '*.yml' -printf '%f\n' 2>/dev/null \
        | sed 's/\.yml$//' \
        | sort -u \
        | tr '\n' ' '
    )"
fi

[ -n "${MAP_LIST// /}" ] || die "No maps found to render. Set MAP_LIST explicitly."
log "Map IDs: ${MAP_LIST}"

if [ "${SKIP_RENDER:-0}" != "1" ]; then
    log "Rendering maps via Content.MapRenderer (--viewer --format=${OUTPUT_FORMAT})"
    # shellcheck disable=SC2086   # intentional word-splitting of MAP_LIST
    dotnet run --project "${MAPRENDERER_PROJECT}" -c Release -- \
        --viewer \
        --format "${OUTPUT_FORMAT}" \
        --output "${RENDER_OUT}" \
        ${MAP_LIST}
else
    log "SKIP_RENDER=1; reusing ${RENDER_OUT}"
fi

# ---------------------------------------------------------------------------
# Stage 2 — build MapViewer
# ---------------------------------------------------------------------------
#
# `vite build --base=/maps/` rewrites asset URLs in index.html so they
# resolve under the /maps/ sub-path. Output goes to <MAPVIEWER_SRC>/dist/
# by default; we point it at <BUILD_OUT> explicitly for isolation.

log "Building MapViewer with vite (base=/maps/)"
pushd "${MAPVIEWER_SRC}" >/dev/null

if [ "${SKIP_NPM_INSTALL:-0}" != "1" ]; then
    log "npm ci"
    npm ci
else
    log "SKIP_NPM_INSTALL=1; reusing node_modules"
fi

# Run vite via npx so we don't need a globally-installed binary. Pass
# --outDir + --emptyOutDir for a clean, deterministic result. `--base`
# controls public asset paths — MUST match the nginx location prefix.
npx vite build \
    --base=/maps/ \
    --outDir "${BUILD_OUT}" \
    --emptyOutDir

popd >/dev/null

# ---------------------------------------------------------------------------
# Stage 3 — assemble bundle
# ---------------------------------------------------------------------------
#
# Layout under BUNDLE_OUT (= served root after rsync):
#
#   index.html              (from MapViewer dist)
#   assets/                 (from MapViewer dist — JS/CSS bundles)
#   *.png / site.webmanifest  (from MapViewer dist — icons)
#   config.json             (ours — ops/mapviewer/config.json)
#   maps/
#     list.json             (generated from MAP_LIST)
#     <MapId>/
#       map.json            (from Content.MapRenderer --viewer)
#       <MapId>-0.webp      (from Content.MapRenderer)

log "Assembling bundle at ${BUNDLE_OUT}"
rm -rf "${BUNDLE_OUT:?}/"*
cp -a "${BUILD_OUT}/." "${BUNDLE_OUT}/"
cp -a "${OPS_CONFIG}" "${BUNDLE_OUT}/config.json"

mkdir -p "${BUNDLE_OUT}/maps"
# Rendered maps — preserve per-map subdirs.
if compgen -G "${RENDER_OUT}/*" >/dev/null; then
    cp -a "${RENDER_OUT}/." "${BUNDLE_OUT}/maps/"
fi

# Generate list.json from rendered dirs (each subdir == one rendered map).
# Keeps the selector honest even if Content.MapRenderer silently skipped a map.
log "Generating maps/list.json"
{
    printf '{\n  "maps": ['
    first=1
    for map_dir in "${BUNDLE_OUT}/maps/"*/; do
        [ -d "${map_dir}" ] || continue
        id="$(basename "${map_dir}")"
        if [ "${first}" = "1" ]; then
            first=0
        else
            printf ','
        fi
        printf '\n    {"name": "%s", "id": "%s"}' "${id}" "${id}"
    done
    printf '\n  ]\n}\n'
} > "${BUNDLE_OUT}/maps/list.json"

# ---------------------------------------------------------------------------
# Stage 4 — publish
# ---------------------------------------------------------------------------
#
# rsync with --delete-after so obsolete maps disappear, but the old
# site keeps serving until the new one is fully in place. --checksum
# avoids needless reuploads on identical content.

log "Publishing to ${SERVE_ROOT}"
mkdir -p "${SERVE_ROOT}"
rsync -a --delete-after --checksum "${BUNDLE_OUT}/" "${SERVE_ROOT}/"

log "Done. MapViewer available at /maps/ (root: ${SERVE_ROOT})"
