#!/usr/bin/env bash
# Vacation Station 14 — RMC14-document-simu deploy pipeline (vs-v69)
#
# Static-site deploy: no build step needed. RMC14-document-simu is
# plain HTML/JS/CSS; its templates ship as a git submodule
# (templates-upstream → crazy1112345/RMC14Paperwork). We:
#   1. Update the document-simu submodule + its own template submodule
#   2. Rsync the static files (+ templates) to /var/www/vs14-writer/
#
# Runs as ss14 user under a weekly systemd timer.

set -euo pipefail

VS14_ROOT="${VS14_ROOT:-/opt/vacation-station}"
VS14_ROOT="$(readlink -f "${VS14_ROOT}")"
SRC="${VS14_ROOT}/external/document-simu"
SERVE_ROOT="${SERVE_ROOT:-/var/www/vs14-writer}"

log() { printf '[writer-build] %s\n' "$*"; }

[ -d "${SRC}" ] || { log "source dir missing: ${SRC}"; exit 1; }

# Sync the submodule to its pinned SHA + pull its template submodule.
# `-c safe.directory='*'` sidesteps the dubious-ownership check git
# applies when the working tree is owned by a different user than the
# invoker (ss14 vs the ubuntu account that typically owns checkouts).
log "updating submodules under ${SRC}"
git -c safe.directory='*' -C "${VS14_ROOT}" submodule update --init --recursive "${SRC}"

# Install the static site. --delete cleans stale files; exclude git
# metadata + the CI + editor dirs that aren't needed at runtime.
log "rsyncing static site to ${SERVE_ROOT}"
rsync -a --delete \
    --exclude '.git*' \
    --exclude '.github' \
    --exclude '.vscode' \
    --exclude 'README.md' \
    --exclude 'LICENSE' \
    --exclude 'update-templates.js' \
    "${SRC}/" \
    "${SERVE_ROOT}/"

log "done. site size: $(du -sh "${SERVE_ROOT}" | awk '{print $1}')"
