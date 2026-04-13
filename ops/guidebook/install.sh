#!/usr/bin/env bash
# Install vs14-guidebook-build systemd unit + timer (vs-1e5).
#
# Idempotent; safe to re-run.
#
# Usage:
#     sudo ./ops/guidebook/install.sh
#
# Prereqs (one-time host setup):
#   - `ss14` system user + group
#   - Repo at /opt/vacation-station (symlink OK)
#   - nginx vhost ops/nginx/ss14.zig.computer.conf installed with
#     /guidebook/ → /var/www/vs14-guidebook/ alias
#   - python3 + pyyaml on PATH for the ss14 user

set -euo pipefail
[ "$(id -u)" = "0" ] || { echo "ERROR: run as root (sudo)" >&2; exit 1; }

OPS_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ">>> installing systemd units"
install -m0644 "${OPS_DIR}/vs14-guidebook-build.service" /etc/systemd/system/
install -m0644 "${OPS_DIR}/vs14-guidebook-build.timer"   /etc/systemd/system/

# Per-host drop-in when /opt/vacation-station is a symlink into /home/*
# (ProtectHome=read-only blocks writes otherwise).
REAL_ROOT="$(readlink -f /opt/vacation-station)"
if [ "${REAL_ROOT}" != "/opt/vacation-station" ]; then
    echo ">>> detected symlinked repo at ${REAL_ROOT}; writing drop-in"
    mkdir -p /etc/systemd/system/vs14-guidebook-build.service.d
    cat > /etc/systemd/system/vs14-guidebook-build.service.d/readwrite-real-path.conf <<EOF
[Service]
ProtectHome=false
EOF
fi

echo ">>> provisioning writable roots (owned by ss14:ss14)"
install -d -o ss14 -g ss14 -m0755 /var/www/vs14-guidebook
install -d -o ss14 -g ss14 -m0755 /var/lib/vs14-guidebook-source

echo ">>> enabling timer"
systemctl daemon-reload
systemctl enable --now vs14-guidebook-build.timer

echo ">>> done. Status:"
systemctl list-timers vs14-guidebook-build.timer --no-pager || true
echo
echo "Force a rebuild with:  sudo systemctl start vs14-guidebook-build.service"
echo "Follow logs with:      journalctl -u vs14-guidebook-build.service -f"
