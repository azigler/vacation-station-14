#!/usr/bin/env bash
# Install vs14-nurseshark-build systemd unit + timer (vs-ygn).
#
# Idempotent; safe to re-run.
#
# Usage:
#     sudo ./ops/nurseshark/install.sh
#
# Prereqs (one-time host setup):
#   - `ss14` system user + group
#   - Repo at /opt/vacation-station (symlink into /home/ubuntu/... OK)
#   - nginx serving /nurseshark/ →
#     /opt/vacation-station/external/nurseshark/dist/. That location
#     block is NOT in this repo: the edge vhost lives in
#     ~/vs14d/ops/nginx/vs14.zig.computer.conf and the per-path
#     routing is on pico's nginx. See ops/nginx/README.md.
#   - Node.js + npm on PATH for the ss14 user (same requirement as
#     ops/cookbook; install via apt or nvm system-wide). Node >= 20.

set -euo pipefail
[ "$(id -u)" = "0" ] || { echo "ERROR: run as root (sudo)" >&2; exit 1; }

OPS_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ">>> installing systemd units"
install -m0644 "${OPS_DIR}/vs14-nurseshark-build.service" /etc/systemd/system/
install -m0644 "${OPS_DIR}/vs14-nurseshark-build.timer"   /etc/systemd/system/

# Per-host drop-in when /opt/vacation-station is a symlink into /home/*.
# ProtectHome=read-only would otherwise block writes into the real
# repo path (npm cache + dist/ + sources.yml all land inside the
# submodule). Same pattern as ops/cookbook + ops/guidebook.
REAL_ROOT="$(readlink -f /opt/vacation-station)"
if [ "${REAL_ROOT}" != "/opt/vacation-station" ]; then
    echo ">>> detected symlinked repo at ${REAL_ROOT}; writing drop-in"
    mkdir -p /etc/systemd/system/vs14-nurseshark-build.service.d
    cat > /etc/systemd/system/vs14-nurseshark-build.service.d/readwrite-real-path.conf <<EOF
[Service]
ReadWritePaths=${REAL_ROOT} ${REAL_ROOT}/external/nurseshark
ProtectHome=false
EOF
fi

echo ">>> provisioning npm cache dir (owned by ss14:ss14)"
install -d -o ss14 -g ss14 -m0755 /var/lib/vs14-nurseshark-cache

echo ">>> enabling timer"
systemctl daemon-reload
systemctl enable --now vs14-nurseshark-build.timer

echo ">>> done. Status:"
systemctl list-timers vs14-nurseshark-build.timer --no-pager || true
echo
echo "Force a rebuild with:  sudo systemctl start vs14-nurseshark-build.service"
echo "Follow logs with:      journalctl -u vs14-nurseshark-build.service -f"
