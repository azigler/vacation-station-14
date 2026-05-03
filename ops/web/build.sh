#!/usr/bin/env bash
# Vacation Station 14 — web/ Next.js build
#
# Installs deps + runs the production Next.js build for the web/ app.
# The build output (web/.next/) is what `vs14-web.service` serves via
# `bun run start` on :3300. Idempotent — safe to re-run.
#
# Usage:
#   sudo -u ss14 /opt/vacation-station/ops/web/build.sh
#
# Rebuild + reload pattern (after a `git pull` brings new web/ code):
#   sudo -u ss14 /opt/vacation-station/ops/web/build.sh
#   sudo systemctl restart vs14-web.service
#
# Runs as the `ss14` system user (same account as the watchdog and
# the daily static-site builders). Bun is invoked by absolute path so
# we don't depend on PATH for non-login shells (the ss14 user has no
# shell profile that adds ~/.bun/bin/).

set -euo pipefail

BUN="${BUN:-/home/ubuntu/.bun/bin/bun}"

cd "$(dirname "$0")/../../web"

echo ">>> bun install --frozen-lockfile"
"${BUN}" install --frozen-lockfile

echo ">>> bun run build"
"${BUN}" run build

echo ">>> done."
