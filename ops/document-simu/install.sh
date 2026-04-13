#!/usr/bin/env bash
# Idempotent installer for the vs14-writer build timer.
set -euo pipefail
[ "$(id -u)" = "0" ] || { echo "run as root" >&2; exit 1; }
OPS_DIR="$(cd "$(dirname "$0")" && pwd)"

install -m0644 "${OPS_DIR}/vs14-writer-build.service" /etc/systemd/system/
install -m0644 "${OPS_DIR}/vs14-writer-build.timer"   /etc/systemd/system/
install -d -o ss14 -g ss14 -m0755 /var/www/vs14-writer

REAL_ROOT="$(readlink -f /opt/vacation-station)"
if [ "${REAL_ROOT}" != "/opt/vacation-station" ]; then
    mkdir -p /etc/systemd/system/vs14-writer-build.service.d
    cat > /etc/systemd/system/vs14-writer-build.service.d/readwrite-real-path.conf <<OVR
[Service]
ReadWritePaths=${REAL_ROOT}
ProtectHome=false
OVR
fi

systemctl daemon-reload
systemctl enable --now vs14-writer-build.timer

echo "done; force rebuild: sudo systemctl start vs14-writer-build.service"
