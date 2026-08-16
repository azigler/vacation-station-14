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
# (served by nginx at https://vs14.zig.computer/maps/rendered/).
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
# Stage 3 — clear stale output, build ONCE, then render PER MAP in docker
# ---------------------------------------------------------------------------
# Rewritten 2026-08-16 (picod bd-204 follow-on): the single all-maps renderer
# process accumulated heap across maps and got SIGKILLed inside the 8GiB
# colima VM mid-run; its `|| true` + the any-output publish gate then rsync
# --delete'd a 1-map partial set over the live maps. Now: the BUILD's exit
# code is respected (SDK-class failures die here, loudly), each map renders
# in its own container process (peak memory = one map), and Stage 4 refuses
# to publish anything less than the full requested set.

rm -rf "${VS14_SOURCE_DIR}/Resources/MapImages"

docker_common=(
    --rm
    --user "$(id -u):$(id -g)"
    --entrypoint sh
    -v "${VS14_SOURCE_DIR}:/work"
    -w /work
    -e DOTNET_CLI_HOME=/tmp
    -e HOME=/tmp
    --ulimit core=0:0
)

log "building Content.MapRenderer"
docker run "${docker_common[@]}" "${IMAGE}" \
    -c "set -e; dotnet build Content.MapRenderer -c Release -v minimal" \
    || die "Content.MapRenderer build failed (SDK/toolchain problem — see log above)"

# Per-map outcome accounting. Three outcomes, and only one of them blocks:
#   produced — a new map dir appeared: rendered.
#   declined — no new dir, but the renderer said 'Creating images for 0 maps'
#              with a clean pass: it EXCLUDES this yml by design (arenas/debug/
#              salvage are utility maps, measured 2026-08-16). Logged, never
#              gates — so adding a real map later keeps full protection.
#   FAILED   — no new dir and no decline marker: crash/OOM/toolchain. Blocks
#              the publish (Stage 4), because rsync --delete would replace the
#              last good set with a hole.
REQUESTED_COUNT=0
FAILED_COUNT=0
DECLINED_COUNT=0
FAILED_MAPS=""
MAP_RUN_LOG="$(mktemp /tmp/map-render-permap.XXXXXX)"
# shellcheck disable=SC2086  # intentional word-splitting of MAP_LIST
for MAP in ${MAP_LIST}; do
    REQUESTED_COUNT=$((REQUESTED_COUNT + 1))
    log "rendering ${MAP} (${REQUESTED_COUNT})"
    dirs_before=$(find "${VS14_SOURCE_DIR}/Resources/MapImages" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    docker run "${docker_common[@]}" "${IMAGE}" \
        -c "./bin/Content.MapRenderer/Content.MapRenderer \
            --format ${OUTPUT_FORMAT} --viewer -f ${MAP} || true" \
        > "${MAP_RUN_LOG}" 2>&1 || true
    cat "${MAP_RUN_LOG}"
    dirs_after=$(find "${VS14_SOURCE_DIR}/Resources/MapImages" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    if [ "${dirs_after}" -gt "${dirs_before}" ]; then
        :
    elif grep -q "Creating images for 0 maps" "${MAP_RUN_LOG}"; then
        DECLINED_COUNT=$((DECLINED_COUNT + 1))
        log "${MAP}: renderer declined (utility map, no images by design)"
    else
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_MAPS="${FAILED_MAPS} ${MAP}"
        log "${MAP}: FAILED (no output, no decline marker)"
    fi
done
rm -f "${MAP_RUN_LOG}"
# RETRY PASS (one, with a settle): the observed per-map failure mode is not
# the map — it is the renderer's own 10s ProcessExited shutdown watchdog
# killing the process before the image write flushes, under late-run VM I/O
# pressure (pair-disposal times climb across sequential containers; measured
# 2026-08-16: maps 17/18 rendered, then died in shutdown, no images). One
# fresh attempt after a settle clears that class; a map that fails BOTH
# passes is a real failure and gates the publish.
if [ "${FAILED_COUNT}" -gt 0 ]; then
    log "retry pass for${FAILED_MAPS} after a 30s settle"
    sleep 30
    RETRY_LIST="${FAILED_MAPS}"
    FAILED_COUNT=0
    FAILED_MAPS=""
    MAP_RUN_LOG="$(mktemp /tmp/map-render-permap.XXXXXX)"
    for MAP in ${RETRY_LIST}; do
        log "retrying ${MAP}"
        dirs_before=$(find "${VS14_SOURCE_DIR}/Resources/MapImages" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
        docker run "${docker_common[@]}" "${IMAGE}" \
            -c "./bin/Content.MapRenderer/Content.MapRenderer \
                --format ${OUTPUT_FORMAT} --viewer -f ${MAP} || true" \
            > "${MAP_RUN_LOG}" 2>&1 || true
        cat "${MAP_RUN_LOG}"
        dirs_after=$(find "${VS14_SOURCE_DIR}/Resources/MapImages" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
        if [ "${dirs_after}" -gt "${dirs_before}" ]; then
            log "${MAP}: rendered on retry"
        elif grep -q "Creating images for 0 maps" "${MAP_RUN_LOG}"; then
            DECLINED_COUNT=$((DECLINED_COUNT + 1))
            log "${MAP}: renderer declined on retry"
        else
            FAILED_COUNT=$((FAILED_COUNT + 1))
            FAILED_MAPS="${FAILED_MAPS} ${MAP}"
            log "${MAP}: FAILED on retry too"
        fi
    done
    rm -f "${MAP_RUN_LOG}"
fi

# Stage 4 — verify + publish
# ---------------------------------------------------------------------------

RENDER_OUT="${VS14_SOURCE_DIR}/Resources/MapImages"
if [ ! -d "${RENDER_OUT}" ]; then
    die "no ${RENDER_OUT} dir produced — renderer didn't start"
fi

RENDERED_COUNT=$(find "${RENDER_OUT}" -type f -name '*.webp' -o -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
RENDERED_DIRS=$(find "${RENDER_OUT}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
if [ "${RENDERED_COUNT}" -eq 0 ]; then
    die "no map images produced — renderer failed before writing anything"
fi

# THE PUBLISH GATE (bd-204 follow-on): publishing uses rsync --delete, so a
# partial render must never reach the serve root — it would REPLACE the last
# good full set (measured 2026-08-16: a SIGKILLed run published one near-empty
# map dir over the live site). Full set or no publish. MIN_RENDERED_DIRS is
# the deliberate override for a known-broken map (set it in the plist, with a
# comment saying which map and why).
if [ "${FAILED_COUNT}" -gt 0 ]; then
    die "partial render: ${FAILED_COUNT} map(s) FAILED (${FAILED_MAPS# }) — ${RENDERED_DIRS} produced, ${DECLINED_COUNT} declined of ${REQUESTED_COUNT} requested. NOT publishing; last good set stays live"
fi

log "rendered ${RENDERED_COUNT} image(s): ${RENDERED_DIRS} maps produced, ${DECLINED_COUNT} declined by the renderer, 0 failed (${REQUESTED_COUNT} requested)"

# Publish directly with --delete (simpler than the staging-rename
# dance, which tripped on .prev-cleanup permissions). Rsync is
# near-atomic at the file level; the slight inconsistency window
# during the copy is acceptable for a weekly static-site rebuild.
mkdir -p "${MAPS_SERVE_ROOT}"
rsync -a --delete "${RENDER_OUT}/" "${MAPS_SERVE_ROOT}/"

MAPS_ROOT="$(dirname "${MAPS_SERVE_ROOT}")"
MAPS_INDEX="${MAPS_ROOT}/index.html"

{
    cat <<'HEADER'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Maps · Vacation Station 14</title>
<style>
  :root { color-scheme: dark; --bg:#0b0f1a; --fg:#e8ecf4; --dim:#9aa7c0; --accent:#6ab0ff; --card:#141b2d; }
  * { box-sizing: border-box; }
  body { margin:0; font-family: system-ui, -apple-system, sans-serif; background: var(--bg); color: var(--fg); line-height: 1.5; padding: 2rem 1rem; }
  .shell { max-width: 80rem; margin: 0 auto; }
  h1 { font-size: clamp(1.75rem, 4vw, 2.5rem); margin: 0 0 0.25rem; letter-spacing: -0.02em; }
  .tag { color: var(--dim); margin: 0 0 2rem; }
  .back { color: var(--accent); text-decoration: none; }
  .back:hover { text-decoration: underline; }
  .maps { display: grid; grid-template-columns: repeat(auto-fill, minmax(18rem, 1fr)); gap: 1rem; }
  .map { background: var(--card); border-radius: 8px; padding: 1rem 1.25rem; }
  .map h2 { font-size: 1.1rem; margin: 0 0 0.5rem; }
  .map .grids { display: grid; grid-template-columns: repeat(auto-fill, minmax(7rem, 1fr)); gap: 0.5rem; margin-bottom: 0.5rem; }
  .map .grid { display: block; aspect-ratio: 1; background: #000 center/contain no-repeat; border-radius: 4px; border: 1px solid #1f2740; transition: transform 0.15s; }
  .map .grid:hover { transform: scale(1.03); border-color: var(--accent); }
  .map .meta { color: var(--dim); font-size: 0.85rem; margin-top: 0.25rem; }
  footer { color: var(--dim); font-size: 0.9rem; border-top: 1px solid #1f2740; padding-top: 1rem; margin-top: 2rem; }
  footer a { color: var(--accent); text-decoration: none; }
</style>
</head>
<body>
<div class="shell">
<p><a class="back" href="/">← Vacation Station 14</a></p>
<h1>Maps</h1>
<p class="tag">Station layouts rendered weekly from the live VS14 build.</p>
<section class="maps">
HEADER

    # One card per map (directory under rendered/). Each grid image in
    # the map dir becomes a tile with a click-through.
    for map_dir in "${MAPS_SERVE_ROOT}"/*/; do
        [ -d "$map_dir" ] || continue
        name="$(basename "$map_dir")"
        printf '<article class="map"><h2>%s</h2><div class="grids">\n' "$name"
        grid_count=0
        for img in "${map_dir}"*.webp "${map_dir}"*.png; do
            [ -f "$img" ] || continue
            rel="rendered/${name}/$(basename "$img")"
            printf '  <a class="grid" href="%s" style="background-image:url(&quot;%s&quot;)" aria-label="%s"></a>\n' \
                "$rel" "$rel" "$(basename "$img")"
            grid_count=$((grid_count + 1))
        done
        printf '</div><div class="meta">%d grid(s)</div></article>\n' "$grid_count"
    done

    cat <<'FOOTER'
</section>
<footer>
<p>Generated by <code>ops/map-render/build.sh</code>. Last rebuild from the latest main push.</p>
</footer>
</div>
</body>
</html>
FOOTER
} > "${MAPS_INDEX}"

log "published to ${MAPS_SERVE_ROOT}, index at ${MAPS_INDEX}"
log "done. size: $(du -sh "${MAPS_ROOT}" 2>/dev/null | awk '{print $1}')"
