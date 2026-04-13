#!/usr/bin/env bash
# Vacation Station 14 — map render pipeline (vs-2nk, Path A)
#
# Runs Content.MapRenderer directly in a Docker container (reusing
# the vs14-mapserver:latest image that already has .NET 10 SDK).
# Sidesteps MapServer's orchestration because Content.MapRenderer
# exits non-zero during cleanup after writing maps — MapServer
# treats that as failure and discards valid output. We check for
# output files regardless of exit code.
#
# Output: WebP images at /var/www/vs14-maps/rendered/<MapName>/<MapName>-N.webp
# (served by nginx at https://ss14.zig.computer/maps/rendered/).
#
# Runs weekly under vs14-map-render.timer as the ss14 user. Manual:
#   sudo systemctl start vs14-map-render.service
#
# Env overrides:
#   VS14_SOURCE_DIR  persistent repo clone (default: /var/cache/vs14-map-render/source)
#   MAPS_SERVE_ROOT  nginx-served output (default: /var/www/vs14-maps/rendered)
#   MAP_LIST         space-separated map YAMLs (default: auto-discover)
#   IMAGE            docker image w/ dotnet 10 + build tools (default: vs14-mapserver:latest)
#   OUTPUT_FORMAT    webp | png (default: webp)

set -uo pipefail

VS14_SOURCE_DIR="${VS14_SOURCE_DIR:-/var/cache/vs14-map-render/source}"
MAPS_SERVE_ROOT="${MAPS_SERVE_ROOT:-/var/www/vs14-maps/rendered}"
IMAGE="${IMAGE:-vs14-mapserver:latest}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-webp}"

log() { printf '[map-render] %s\n' "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Stage 1 — fetch / update the VS14 source clone
# ---------------------------------------------------------------------------

mkdir -p "$(dirname "${VS14_SOURCE_DIR}")"

if [ ! -d "${VS14_SOURCE_DIR}/.git" ]; then
    log "cloning VS14 into ${VS14_SOURCE_DIR}"
    git clone https://github.com/azigler/vacation-station-14 "${VS14_SOURCE_DIR}" \
        || die "clone failed"
else
    log "updating ${VS14_SOURCE_DIR}"
    git -c safe.directory='*' -C "${VS14_SOURCE_DIR}" fetch origin main \
        || die "fetch failed"
    git -c safe.directory='*' -C "${VS14_SOURCE_DIR}" reset --hard origin/main \
        || die "reset failed"
fi

# We only need RobustToolbox for the build; external/* submodules have
# nested SSH-gated submodules of their own (mapserver's
# SS14.GithubApiHelper, etc.) that would break an unauthenticated clone.
# Init RobustToolbox + its own dependencies, skip everything under external/.
log "initializing RobustToolbox submodule (recursive)"
git -c safe.directory='*' -C "${VS14_SOURCE_DIR}" submodule update --init --recursive RobustToolbox \
    || die "RobustToolbox submodule update failed"

# ---------------------------------------------------------------------------
# Stage 2 — discover maps
# ---------------------------------------------------------------------------

if [ -z "${MAP_LIST:-}" ]; then
    MAP_LIST="$(
        find "${VS14_SOURCE_DIR}/Resources/Prototypes/Maps" \
             -maxdepth 1 -type f -name '*.yml' -printf '%f\n' 2>/dev/null \
        | sort -u | tr '\n' ' '
    )"
fi
[ -n "${MAP_LIST// /}" ] || die "no maps found"
log "rendering ${MAP_LIST}"

# ---------------------------------------------------------------------------
# Stage 3 — clear stale output, build + run renderer in docker
# ---------------------------------------------------------------------------

rm -rf "${VS14_SOURCE_DIR}/Resources/MapImages"

# shellcheck disable=SC2086  # intentional word-splitting of MAP_LIST
docker run --rm \
    --user "$(id -u):$(id -g)" \
    --entrypoint sh \
    -v "${VS14_SOURCE_DIR}:/work" \
    -w /work \
    -e DOTNET_CLI_HOME=/tmp \
    -e HOME=/tmp \
    --ulimit core=0:0 \
    "${IMAGE}" \
    -c "
        set -e
        echo '[map-render:container] build'
        dotnet build Content.MapRenderer -c Release -v minimal
        echo '[map-render:container] render'
        # Exit code of the renderer is ignored; output presence is what
        # matters. '|| true' keeps the outer docker exit code clean.
        ./bin/Content.MapRenderer/Content.MapRenderer \
            --format ${OUTPUT_FORMAT} \
            --viewer \
            -f ${MAP_LIST} \
            || true
    "
DOCKER_RC=$?
log "docker exit code: ${DOCKER_RC} (ignored; output presence is what counts)"

# ---------------------------------------------------------------------------
# Stage 4 — verify + publish
# ---------------------------------------------------------------------------

RENDER_OUT="${VS14_SOURCE_DIR}/Resources/MapImages"
if [ ! -d "${RENDER_OUT}" ]; then
    die "no ${RENDER_OUT} dir produced — renderer didn't start"
fi

RENDERED_COUNT=$(find "${RENDER_OUT}" -type f -name '*.webp' -o -name '*.png' 2>/dev/null | wc -l)
if [ "${RENDERED_COUNT}" -eq 0 ]; then
    die "no map images produced — renderer failed before writing anything"
fi

log "rendered ${RENDERED_COUNT} map image(s)"

# Atomic publish: rsync to a staging dir then rename into place.
STAGING="${MAPS_SERVE_ROOT}.tmp.$$"
mkdir -p "$(dirname "${MAPS_SERVE_ROOT}")"
rsync -a --delete "${RENDER_OUT}/" "${STAGING}/"
rm -rf "${MAPS_SERVE_ROOT}.prev" 2>/dev/null || true
if [ -d "${MAPS_SERVE_ROOT}" ]; then
    mv "${MAPS_SERVE_ROOT}" "${MAPS_SERVE_ROOT}.prev"
fi
mv "${STAGING}" "${MAPS_SERVE_ROOT}"

log "published to ${MAPS_SERVE_ROOT}"
log "done. size: $(du -sh "${MAPS_SERVE_ROOT}" 2>/dev/null | awk '{print $1}')"
