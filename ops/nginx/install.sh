#!/usr/bin/env bash
# Install the ss14.zig.computer nginx vhost — safely, preserving
# certbot's :443 server block (vs-15s).
#
# Problem this solves: the committed template in this repo is
# HTTP-only by design (certs don't belong in source control). On
# first install, certbot rewrites the file in place to add a :443
# server block. A naive re-install (``sudo install -m 0644
# ops/nginx/*.conf /etc/nginx/sites-available/``) clobbers the
# certbot-shaped copy and takes HTTPS offline — exactly what
# happened at the tail of vs-1e5 before this script existed.
#
# This script:
#   1. Installs the HTTP-only template from the repo.
#   2. Re-runs ``certbot --nginx`` to re-shape the file (no-op if
#      cert already exists and is current; it just redeploys).
#   3. ``nginx -t`` + ``systemctl reload nginx``.
#
# Re-running is idempotent. Certbot's --expand / --redirect flags
# handle the "already shaped" case cleanly.
#
# Usage:
#     sudo ./ops/nginx/install.sh
#
# Every service whose install.sh adds / edits a ``location`` block
# in ``ops/nginx/ss14.zig.computer.conf`` MUST re-run this script
# (or tell the operator to) after the template change lands.

set -euo pipefail
[ "$(id -u)" = "0" ] || { echo "ERROR: run as root (sudo)" >&2; exit 1; }

HOST="ss14.zig.computer"
OPS_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="${OPS_DIR}/${HOST}.conf"
TARGET="/etc/nginx/sites-available/${HOST}.conf"
ENABLED="/etc/nginx/sites-enabled/${HOST}.conf"

[ -f "${TEMPLATE}" ] || { echo "ERROR: template missing: ${TEMPLATE}" >&2; exit 1; }

echo ">>> installing vhost template to ${TARGET}"
install -m 0644 "${TEMPLATE}" "${TARGET}"
ln -sf "${TARGET}" "${ENABLED}"

if sudo -n test -d "/etc/letsencrypt/live/${HOST}" 2>/dev/null \
    || [ -d "/etc/letsencrypt/live/${HOST}" ]; then
    echo ">>> cert exists for ${HOST}; re-shaping vhost via certbot (--expand --redirect)"
    certbot --nginx -d "${HOST}" \
        --non-interactive --expand --redirect --agree-tos \
        --register-unsafely-without-email
else
    echo ">>> no cert yet for ${HOST}; issuing + shaping via certbot"
    echo "    (requires DNS pointing at this host + ports 80/443 reachable)"
    certbot --nginx -d "${HOST}" \
        --non-interactive --expand --redirect --agree-tos \
        --register-unsafely-without-email
fi

echo ">>> validating + reloading nginx"
nginx -t
systemctl reload nginx

echo
echo ">>> done. Active server blocks:"
grep -E "listen|server_name" "${TARGET}" | sed 's/^/    /'
