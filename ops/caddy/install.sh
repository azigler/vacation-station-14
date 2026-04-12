#!/bin/bash
# Vacation Station 14 — Caddy install + initial configuration
#
# Run ONCE on the production host after:
#   - A domain has been chosen
#   - DNS for download.<DOMAIN> + admin.<DOMAIN> resolves to this host
#   - The chosen domain has been filled into ops/caddy/Caddyfile
#     (replace <DOMAIN> placeholder).
#
# This script:
#   1. Installs caddy from the official caddy apt repo
#   2. Copies ops/caddy/Caddyfile to /etc/caddy/Caddyfile
#   3. Opens ufw 80/443, enables + starts caddy
#
# After the script:
#   - Update /opt/ss14-watchdog/appsettings.yml (BaseUrl + Urls) per
#     ops/caddy/Caddyfile's header comment
#   - Restart watchdog
#   - Smoke-test download.<DOMAIN>/client.zip + admin.<DOMAIN> (with
#     ApiToken) from an external machine
#   - Close ufw :5000:  sudo ufw delete allow 5000/tcp

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if grep -q '<DOMAIN>' "${REPO_ROOT}/ops/caddy/Caddyfile"; then
    echo "ABORT: <DOMAIN> placeholder not replaced in ops/caddy/Caddyfile." >&2
    echo "Edit the Caddyfile first; pick a real domain." >&2
    exit 1
fi

# --- Install caddy (from official apt repo) ---

if ! command -v caddy >/dev/null 2>&1; then
    echo ">>> Installing caddy from the official apt repository"
    sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
        | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
        | sudo tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y caddy
else
    echo ">>> caddy already installed"
fi

# --- Drop Caddyfile into place ---

sudo cp "${REPO_ROOT}/ops/caddy/Caddyfile" /etc/caddy/Caddyfile

# --- Firewall ---

sudo ufw allow 80/tcp comment 'caddy http'
sudo ufw allow 443/tcp comment 'caddy https'

# --- Enable + start ---

sudo systemctl enable caddy
sudo systemctl restart caddy
sleep 2
sudo systemctl status caddy --no-pager -n 5 | head -10

echo
echo ">>> Caddy install complete."
echo ">>> Next:"
echo "      1. Edit /opt/ss14-watchdog/appsettings.yml"
echo "         BaseUrl: https://download.<DOMAIN>/"
echo "         Urls:    http://127.0.0.1:5000"
echo "      2. sudo systemctl restart ss14-watchdog"
echo "      3. Smoke-test from external host, then:"
echo "         sudo ufw delete allow 5000/tcp"
