#!/bin/bash
# Vacation Station 14 — SS14.Watchdog build + install
#
# Clones upstream SS14.Watchdog ("Ian"), publishes a linux-x64 framework-
# dependent build, installs it under /opt/ss14-watchdog/, and registers
# the systemd unit from ops/watchdog/. Does NOT start the service —
# operators must populate appsettings.yml + create the ss14 user's
# instance data first.
#
# Usage:
#   sudo ./setup.watchdog.sh                      # build from master
#   sudo WATCHDOG_REF=v1.2.3 ./setup.watchdog.sh  # pin a tag/commit
#
# Idempotent. Re-runs update the binary in place. The generated ApiToken
# in appsettings.yml is preserved across re-runs; rotate manually.
#
# Prereqs: .NET 10 SDK (setup.ubuntu.sh --server installs it), git,
# rsync, openssl. All are apt-installable.
#
# Tested on Ubuntu 24.04 LTS.

set -euo pipefail

WATCHDOG_REF="${WATCHDOG_REF:-master}"
WATCHDOG_REPO="${WATCHDOG_REPO:-https://github.com/space-wizards/SS14.Watchdog}"
INSTALL_DIR="${INSTALL_DIR:-/opt/ss14-watchdog}"
BUILD_DIR="${BUILD_DIR:-/var/tmp/ss14-watchdog-build}"

SS14_USER="${SS14_USER:-ss14}"
SS14_GROUP="${SS14_GROUP:-ss14}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
UNIT_SRC="${SCRIPT_DIR}/ops/watchdog/ss14-watchdog.service"
APPSETTINGS_TEMPLATE="${SCRIPT_DIR}/ops/watchdog/appsettings.yml.example"
UNIT_DST="/etc/systemd/system/ss14-watchdog.service"

# --- Preflight --------------------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: must run as root (sudo)." >&2
    exit 1
fi

for bin in git rsync openssl dotnet; do
    if ! command -v "${bin}" >/dev/null 2>&1; then
        echo "Error: '${bin}' not found in PATH." >&2
        if [ "${bin}" = "dotnet" ]; then
            echo "       Run 'sudo ./setup.ubuntu.sh --server' first to install .NET 10 SDK." >&2
        fi
        exit 1
    fi
done

if [ ! -f "${UNIT_SRC}" ]; then
    echo "Error: systemd unit not found at ${UNIT_SRC}" >&2
    exit 1
fi
if [ ! -f "${APPSETTINGS_TEMPLATE}" ]; then
    echo "Error: appsettings template not found at ${APPSETTINGS_TEMPLATE}" >&2
    exit 1
fi

# --- User / group -----------------------------------------------------------

if ! getent group "${SS14_GROUP}" >/dev/null 2>&1; then
    echo ">>> Creating group '${SS14_GROUP}'..."
    groupadd --system "${SS14_GROUP}"
fi
if ! id -u "${SS14_USER}" >/dev/null 2>&1; then
    echo ">>> Creating user '${SS14_USER}' (system, no shell, home=${INSTALL_DIR})..."
    useradd --system --gid "${SS14_GROUP}" \
        --home-dir "${INSTALL_DIR}" --no-create-home \
        --shell /usr/sbin/nologin "${SS14_USER}"
fi

# --- Clone / update source --------------------------------------------------

echo ">>> Fetching SS14.Watchdog (ref: ${WATCHDOG_REF})..."
mkdir -p "${BUILD_DIR}"
if [ -d "${BUILD_DIR}/.git" ]; then
    git -C "${BUILD_DIR}" fetch --tags --prune origin
else
    # Start over if the directory exists but isn't a git checkout.
    rm -rf "${BUILD_DIR}"
    git clone "${WATCHDOG_REPO}" "${BUILD_DIR}"
fi
git -C "${BUILD_DIR}" checkout --detach "${WATCHDOG_REF}"
git -C "${BUILD_DIR}" submodule update --init --recursive

# --- Publish ----------------------------------------------------------------
#
# The exact publish invocation matters: `--no-self-contained` (framework-
# dependent) preserves the execute bit on Mono.Posix.NETStandard.dll's
# underlying native helpers. Self-contained publishes have historically
# tripped over this; upstream docs call it out explicitly.

echo ">>> Publishing (dotnet publish -c Release -r linux-x64 --no-self-contained)..."
PUBLISH_OUT="${BUILD_DIR}/publish"
rm -rf "${PUBLISH_OUT}"

# DOTNET_CLI_HOME: .NET wants a writable home; root's may be read-only in
# some container/minimal setups. /tmp matches the systemd unit's env.
DOTNET_CLI_HOME=/tmp dotnet publish \
    "${BUILD_DIR}/SS14.Watchdog/SS14.Watchdog.csproj" \
    -c Release \
    -r linux-x64 \
    --no-self-contained \
    -o "${PUBLISH_OUT}"

if [ ! -f "${PUBLISH_OUT}/SS14.Watchdog" ]; then
    echo "Error: publish did not produce ${PUBLISH_OUT}/SS14.Watchdog" >&2
    exit 1
fi

# --- Install ----------------------------------------------------------------

echo ">>> Installing to ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}"
# --delete so we don't leave stale files from previous builds, but keep
# runtime-owned state by excluding appsettings + instances.
rsync -a --delete \
    --exclude='appsettings.yml' \
    --exclude='instances/' \
    --exclude='logs/' \
    "${PUBLISH_OUT}/" "${INSTALL_DIR}/"

chmod +x "${INSTALL_DIR}/SS14.Watchdog"

# --- appsettings.yml --------------------------------------------------------

APPSETTINGS_DST="${INSTALL_DIR}/appsettings.yml"
if [ -f "${APPSETTINGS_DST}" ]; then
    echo ">>> appsettings.yml already exists — leaving ApiToken alone."
    GENERATED_TOKEN=""
else
    echo ">>> Generating ApiToken + installing appsettings.yml..."
    GENERATED_TOKEN="$(openssl rand -hex 32)"
    # Stream the template through sed into the destination so the token
    # never lands on disk in an intermediate file.
    sed "s|REPLACE_WITH_GENERATED_TOKEN|${GENERATED_TOKEN}|" \
        "${APPSETTINGS_TEMPLATE}" > "${APPSETTINGS_DST}"
    chmod 0640 "${APPSETTINGS_DST}"
fi

# --- Log dir + ownership ----------------------------------------------------

install -d -o "${SS14_USER}" -g "${SS14_GROUP}" -m 0755 /var/log/ss14-watchdog
install -d -o "${SS14_USER}" -g "${SS14_GROUP}" -m 0755 "${INSTALL_DIR}/instances"

chown -R "${SS14_USER}:${SS14_GROUP}" "${INSTALL_DIR}"

# --- systemd unit -----------------------------------------------------------

echo ">>> Installing systemd unit to ${UNIT_DST}..."
install -m 0644 "${UNIT_SRC}" "${UNIT_DST}"
systemctl daemon-reload
systemctl enable ss14-watchdog.service

# --- Summary ----------------------------------------------------------------

echo ""
echo "==============================================="
echo "  SS14.Watchdog install complete"
echo "==============================================="
echo "  Ref:         ${WATCHDOG_REF}"
echo "  Install dir: ${INSTALL_DIR}"
echo "  User/Group:  ${SS14_USER}:${SS14_GROUP}"
echo "  Unit:        ${UNIT_DST} (enabled, NOT started)"
echo ""

if [ -n "${GENERATED_TOKEN}" ]; then
    echo ">>> Generated ApiToken for instance 'vacation-station':"
    echo ""
    echo "    ${GENERATED_TOKEN}"
    echo ""
    echo "    STORE THIS IN YOUR PASSWORD MANAGER NOW."
    echo "    Re-running this script will NOT rotate it. To rotate: edit"
    echo "    ${APPSETTINGS_DST}"
    echo "    then 'systemctl restart ss14-watchdog'."
    echo ""
fi

echo ">>> Next steps:"
echo "    1. Bootstrap the instance data layout:"
echo "         sudo ./ops/watchdog/instance-bootstrap.sh"
echo "    2. Edit the instance config (fill postgres password):"
echo "         ${INSTALL_DIR}/instances/vacation-station/config.toml"
echo "    3. Drop a Robust.Server publish into:"
echo "         ${INSTALL_DIR}/instances/vacation-station/binaries/"
echo "    4. Start the watchdog:"
echo "         sudo systemctl start ss14-watchdog"
echo "    5. Verify:  systemctl is-active ss14-watchdog"
echo "               curl -sSf http://localhost:5000/instances/vacation-station/status"
echo ""
