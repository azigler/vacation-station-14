#!/usr/bin/env bash
# Install vs14-map-render systemd unit + timer (vs-2nk Path A)
set -euo pipefail
[ "$(id -u)" = "0" ] || { echo "run as root" >&2; exit 1; }

OPS_DIR="$(cd "$(dirname "$0")" && pwd)"

install -m0644 "${OPS_DIR}/vs14-map-render.service" /etc/systemd/system/
install -m0644 "${OPS_DIR}/vs14-map-render.timer"   /etc/systemd/system/
install -d -o ss14 -g ss14 -m0755 /var/cache/vs14-map-render
install -d -o ss14 -g ss14 -m0755 /var/www/vs14-maps

# Per-host drop-in when /opt/vacation-station is a symlink into /home/*
REAL_ROOT="$(readlink -f /opt/vacation-station)"
if [ "${REAL_ROOT}" != "/opt/vacation-station" ]; then
    mkdir -p /etc/systemd/system/vs14-map-render.service.d
    cat > /etc/systemd/system/vs14-map-render.service.d/readwrite-real-path.conf <<EOF
[Service]
ProtectHome=false
EOF
fi

# ss14 needs docker group membership to `docker run`
if ! id -nG ss14 | grep -qw docker; then
    usermod -aG docker ss14
    echo "added ss14 to docker group"
fi

systemctl daemon-reload
systemctl enable --now vs14-map-render.timer

echo "done; force run: sudo systemctl start vs14-map-render.service"
