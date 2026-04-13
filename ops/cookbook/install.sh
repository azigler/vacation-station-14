#!/bin/bash
# Vacation Station 14 — cookbook systemd install helper
#
# Installs the vs14-cookbook-build systemd units onto a production
# host, provisions the writable roots under the ss14 user, and enables
# the daily timer. Idempotent — safe to re-run.
#
# Usage:
#     sudo ./ops/cookbook/install.sh
#
# Prerequisites (not handled here — one-time host setup):
#   - `ss14` system user + group exist (see setup.watchdog.sh)
#   - Repo is checked out or symlinked at /opt/vacation-station
#   - nginx vhost ops/nginx/ss14.zig.computer.conf is live and aliases
#     /recipes/ → /var/www/vs14-recipes/
#   - Node.js + npm on PATH for the ss14 user (the build.sh call
#     inherits the service's env; install node via apt or nvm
#     system-wide)

set -euo pipefail

if [ "$(id -u)" != "0" ]; then
    echo "ERROR: run as root (sudo)" >&2
    exit 1
fi

OPS_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ">>> installing systemd units"
install -m0644 "${OPS_DIR}/vs14-cookbook-build.service" /etc/systemd/system/
install -m0644 "${OPS_DIR}/vs14-cookbook-build.timer"   /etc/systemd/system/

# If /opt/vacation-station is a symlink (common on dev hosts where the
# repo lives under /home/<user>/...), the build needs the real path in
# ReadWritePaths because `ProtectHome=read-only` blocks writes to
# anything under /home by default. Write a drop-in override with the
# real path so the same committed unit file works on both layouts.
REAL_ROOT="$(readlink -f /opt/vacation-station)"
if [ "${REAL_ROOT}" != "/opt/vacation-station" ]; then
    echo ">>> detected symlinked repo: ${REAL_ROOT}"
    mkdir -p /etc/systemd/system/vs14-cookbook-build.service.d
    cat > /etc/systemd/system/vs14-cookbook-build.service.d/readwrite-real-path.conf <<EOF
[Service]
ReadWritePaths=${REAL_ROOT}/external/cookbook
ProtectHome=false
EOF
fi

echo ">>> provisioning writable roots (owned by ss14:ss14)"
install -d -o ss14 -g ss14 -m0755 /var/www/vs14-recipes
install -d -o ss14 -g ss14 -m0755 /var/lib/vs14-cookbook-source

echo ">>> enabling timer"
systemctl daemon-reload
systemctl enable --now vs14-cookbook-build.timer

echo ">>> done. Status:"
systemctl list-timers vs14-cookbook-build.timer --no-pager || true
echo
echo "Force a rebuild with:  sudo systemctl start vs14-cookbook-build.service"
echo "Follow logs with:      journalctl -u vs14-cookbook-build.service -f"
