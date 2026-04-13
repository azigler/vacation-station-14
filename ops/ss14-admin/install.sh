#!/usr/bin/env bash
# Bring up SS14.Admin (vs-35d) — idempotent.
#
# What this does:
#   1. Validates that /etc/vacation-station/admin-oauth.env exists (OIDC creds).
#   2. Validates that ops/ss14-admin/.env exists (POSTGRES_PASSWORD).
#   3. Ensures a live appsettings.yml exists next to the
#      committed .example (copies if missing; never overwrites).
#   4. docker compose pull/build/up -d, then waits for healthy.
#   5. Prints the container status. Does NOT echo secrets.
#
# nginx route install is separate — run `sudo ops/nginx/install.sh`
# after the vhost template changes land.
#
# Usage:
#     ./ops/ss14-admin/install.sh
#
# Re-running is safe: pull is idempotent, build caches, up -d is no-op
# if nothing changed.

set -euo pipefail

OPS_DIR="$(cd "$(dirname "$0")" && pwd)"
OAUTH_ENV="/etc/vacation-station/admin-oauth.env"
LOCAL_ENV="${OPS_DIR}/.env"
LIVE_CFG="${OPS_DIR}/appsettings.yml"
EXAMPLE_CFG="${OPS_DIR}/appsettings.yml.example"

echo ">>> checking OIDC creds env file"
if [ ! -r "${OAUTH_ENV}" ]; then
    echo "ERROR: ${OAUTH_ENV} not readable by $(id -un)." >&2
    echo "       Expected mode 640 owned by root:ss14 with OIDC_CLIENT_ID +" >&2
    echo "       OIDC_CLIENT_SECRET populated. See docs/OPERATIONS.md." >&2
    exit 1
fi
# Do NOT cat the file — journald would capture the secret. Just confirm
# the two required keys are present (grep -q is silent).
if ! grep -q '^OIDC_CLIENT_ID=' "${OAUTH_ENV}" \
    || ! grep -q '^OIDC_CLIENT_SECRET=' "${OAUTH_ENV}"; then
    echo "ERROR: ${OAUTH_ENV} missing OIDC_CLIENT_ID or OIDC_CLIENT_SECRET." >&2
    exit 1
fi

echo ">>> checking ops/ss14-admin/.env"
if [ ! -f "${LOCAL_ENV}" ]; then
    echo "ERROR: ${LOCAL_ENV} missing. Copy from .env.example and fill in" >&2
    echo "       POSTGRES_PASSWORD." >&2
    exit 1
fi
if ! grep -Eq '^POSTGRES_PASSWORD=.+' "${LOCAL_ENV}"; then
    echo "ERROR: POSTGRES_PASSWORD is empty in ${LOCAL_ENV}." >&2
    exit 1
fi

echo ">>> ensuring live appsettings.yml"
if [ ! -f "${LIVE_CFG}" ]; then
    install -m 0644 "${EXAMPLE_CFG}" "${LIVE_CFG}"
    echo "    (seeded from .example; edit ${LIVE_CFG} for local tweaks)"
fi

# docker-compose does variable interpolation (${OIDC_CLIENT_ID:?...}) at
# parse time from the CALLER's environment. env_file: in the compose only
# affects container runtime. Load the OAuth creds into this script's
# process env so compose sees them; they never appear in journald because
# we don't echo and the values don't go through argv.
set -a
# shellcheck source=/dev/null
. "${OAUTH_ENV}"
# shellcheck source=/dev/null
. "${LOCAL_ENV}"
set +a

echo ">>> pulling + building image"
docker compose -f "${OPS_DIR}/docker-compose.yml" pull --ignore-buildable
docker compose -f "${OPS_DIR}/docker-compose.yml" build

echo ">>> bringing stack up"
docker compose -f "${OPS_DIR}/docker-compose.yml" up -d

echo ">>> waiting for container to settle (up to 90s)"
for _ in $(seq 1 18); do
    status=$(docker inspect --format '{{.State.Health.Status}}' vs14-ss14-admin 2>/dev/null || echo "missing")
    case "${status}" in
        healthy) echo "    healthy."; break ;;
        unhealthy) echo "ERROR: container went unhealthy. Check logs." >&2; exit 1 ;;
        *) sleep 5 ;;
    esac
done

echo
echo ">>> container status:"
docker compose -f "${OPS_DIR}/docker-compose.yml" ps

echo
echo ">>> Next steps:"
echo "    - First admin bootstrap: log in once via the browser, then"
echo "      run the UUID-harvest flow documented in docs/OPERATIONS.md"
echo "      (SS14.Admin section)."
echo "    - nginx: ensure ops/nginx/install.sh has been run since the"
echo "      /admin/ location block was added."
