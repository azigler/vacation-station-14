#!/usr/bin/env bash
# Vacation Station 14 — nurseshark static-site build (vs-ygn)
#
# Builds the first-party chemistry/medical/cryo companion app (Vite +
# React, TypeScript) from the external/nurseshark submodule and serves
# it out of that submodule's dist/ directory. nginx fronts the output
# at https://ss14.zig.computer/nurseshark/ (see
# ops/nginx/ss14.zig.computer.conf).
#
# Unlike ops/cookbook and ops/guidebook, nurseshark does NOT use a
# sibling source clone — the submodule itself embeds the VS14 parent
# repo as its data source. The data pipeline (`npm run gen`) reads
# Resources/ from the VS14 checkout directly via sources.yml.
#
# Idempotent; safe to re-run. Driven by vs14-nurseshark-build.timer
# (daily, 05:00 UTC after pg_dump 03:15 + replay-rotate 04:30). Manual:
#     sudo systemctl start vs14-nurseshark-build.service
#
# Env knobs (all optional; defaults mirror the systemd unit):
#   REPO_ROOT              deploy checkout root
#                          (default: /opt/vacation-station)
#   NURSESHARK_BASE_PATH   URL path prefix baked into the Vite bundle
#                          (default: /nurseshark/)
#
# --- vs-ygn.1: VITE_BASE_PATH discipline ---
# Vite rewrites `<script src>` / `<link href>` in dist/index.html to
# honor `base` (set from VITE_BASE_PATH here). Without it, the bundle
# references root-relative `/assets/*`, which 404s under nginx's
# `/nurseshark/` alias. A post-build grep check enforces this: if the
# base path didn't bake in, the whole build fails non-zero and the
# previous dist/ stays served.
#
# --- vs-ygn.2: nginx SPA fallback is nginx-side ---
# This script produces the artifact; nginx's `try_files $uri $uri/
# /nurseshark/index.html` handles BrowserRouter deep-links. See the
# /nurseshark/ location block in ops/nginx/ss14.zig.computer.conf.

set -euo pipefail

# Ensure nvm-installed node toolchain is on PATH for timer-spawned
# invocations (systemd timers get a minimal default PATH that excludes
# /home/ubuntu/.nvm/.../bin). Idempotent: skipped when npm is already
# resolvable (interactive shells via .zshrc init). See vs-9an.
if ! command -v npm >/dev/null 2>&1; then
  newest_node_bin=$(ls -1dt /home/ubuntu/.nvm/versions/node/*/bin 2>/dev/null | head -1)
  if [ -n "${newest_node_bin:-}" ]; then
    export PATH="${newest_node_bin}:${PATH}"
  fi
fi

REPO_ROOT="${REPO_ROOT:-/opt/vacation-station}"
NURSESHARK_BASE_PATH="${NURSESHARK_BASE_PATH:-/nurseshark/}"

NURSESHARK_DIR="${REPO_ROOT}/external/nurseshark"

log() { printf '[nurseshark] %s\n' "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

# --- 1. Refresh VS14 checkout + submodule pin ---
# Nurseshark's SHA is tracked in the VS14 repo; a `git pull` on the
# parent plus `submodule update` pulls any bumped pin automatically.
# We deliberately run --init --recursive scoped to the nurseshark
# submodule only (no need to poke RobustToolbox on every timer).

log "refreshing VS14 checkout at ${REPO_ROOT}"
git -c safe.directory='*' -C "${REPO_ROOT}" pull --rebase --autostash
git -c safe.directory='*' -C "${REPO_ROOT}" submodule update --init --recursive external/nurseshark

[ -d "${NURSESHARK_DIR}" ] || die "nurseshark submodule missing at ${NURSESHARK_DIR}"
[ -f "${NURSESHARK_DIR}/package.json" ] || die "${NURSESHARK_DIR}/package.json missing (submodule not initialized?)"

# --- 2. Write sources.yml for the data pipeline ---
# sources.yml is gitignored per-operator. Point it at the VS14 repo
# we just refreshed above. `commit_context: auto` reads the HEAD SHA
# for meta.json so the footer can show "data generated from <sha>".

log "writing ${NURSESHARK_DIR}/sources.yml (vs14 path=${REPO_ROOT})"
cat > "${NURSESHARK_DIR}/sources.yml" <<EOF
sources:
  vs14:
    path: "${REPO_ROOT}"
    commit_context: "auto"
EOF

cd "${NURSESHARK_DIR}"

# --- 3. Install deps ---
# `npm install --silent` is idempotent; re-runs are fast when
# package-lock.json hasn't changed.

log "npm install"
npm install --silent --no-audit --no-fund

# --- 4. Generate public/data/*.json from VS14 YAML ---

log "npm run gen"
npm run gen

# --- 5. Build static bundle — VITE_BASE_PATH gate (vs-ygn.1) ---
# Inline the env var on the build command so it can't leak into
# subsequent `npm run dev` sessions if an operator re-enters the dir.

log "npm run build (VITE_BASE_PATH=${NURSESHARK_BASE_PATH})"
VITE_BASE_PATH="${NURSESHARK_BASE_PATH}" npm run build

# --- 6. Post-build grep check (vs-ygn.1 gate) ---
# If VITE_BASE_PATH didn't bake in, dist/index.html will reference
# `/assets/*` instead of `/nurseshark/assets/*`. Fail the whole build
# loudly — better to keep the old dist/ served than to ship broken
# asset paths. The grep pattern matches the exact prefix we need.

EXPECTED="${NURSESHARK_BASE_PATH%/}/assets/"  # e.g. "/nurseshark/assets/"

[ -f "${NURSESHARK_DIR}/dist/index.html" ] \
    || die "build produced no dist/index.html"

if ! grep -q "${EXPECTED}" "${NURSESHARK_DIR}/dist/index.html"; then
    die "dist/index.html does not reference '${EXPECTED}' — VITE_BASE_PATH did not bake in. Refusing to publish."
fi

log "dist/index.html references ${EXPECTED} — base path baked in cleanly"

# nginx does NOT need a reload here. The vhost points at dist/ via
# `alias`, so fresh files are served as soon as the atomic rename that
# `vite build` performs completes. Reloading nginx is an install-time
# concern (when the vhost template itself changes) — handled by
# ops/nginx/install.sh.

log "done."
