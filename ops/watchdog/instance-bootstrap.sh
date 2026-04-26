#!/bin/bash
# Vacation Station 14 — watchdog instance bootstrap
#
# Creates the on-disk layout SS14.Watchdog expects for the
# "vacation-station" instance:
#
#   /opt/ss14-watchdog/instances/vacation-station/
#       config.toml        (seeded from the repo's config.toml.example
#                           if not already present — operator must then
#                           edit it to fill in the postgres password)
#
# vs-2f8.1 retired the legacy `binaries/` drop target — Manifest mode now
# pulls builds from our Robust.Cdn (https://ss14.zig.computer/cdn/), so
# the operator never hand-publishes into the instance dir. The watchdog
# downloads versioned builds into its own working directory.
#
# Idempotent. Re-runs do NOT overwrite existing config.toml — that file
# holds the DB password and must not be clobbered.
#
# Usage:
#   sudo ./ops/watchdog/instance-bootstrap.sh
#
# Tested on Ubuntu 24.04 LTS.

set -euo pipefail

WATCHDOG_ROOT="${WATCHDOG_ROOT:-/opt/ss14-watchdog}"
INSTANCE_NAME="${INSTANCE_NAME:-vacation-station}"
INSTANCE_DIR="${WATCHDOG_ROOT}/instances/${INSTANCE_NAME}"

SS14_USER="${SS14_USER:-ss14}"
SS14_GROUP="${SS14_GROUP:-ss14}"

# Resolve the repo root from this script's own location so the operator
# can run it from anywhere.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
CONFIG_TEMPLATE="${REPO_ROOT}/instances/${INSTANCE_NAME}/config.toml.example"

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: must run as root (sudo)." >&2
    exit 1
fi

if [ ! -f "${CONFIG_TEMPLATE}" ]; then
    echo "Error: config template not found at ${CONFIG_TEMPLATE}" >&2
    exit 1
fi

echo ">>> Creating instance layout under ${INSTANCE_DIR}..."
install -d -o "${SS14_USER}" -g "${SS14_GROUP}" -m 0755 "${INSTANCE_DIR}"

TARGET_CONFIG="${INSTANCE_DIR}/config.toml"
if [ -f "${TARGET_CONFIG}" ]; then
    echo "    (config.toml already exists, leaving alone)"
else
    echo ">>> Seeding config.toml from template..."
    install -o "${SS14_USER}" -g "${SS14_GROUP}" -m 0640 \
        "${CONFIG_TEMPLATE}" "${TARGET_CONFIG}"
    echo "    Wrote ${TARGET_CONFIG}"
    echo "    Edit it to fill in the postgres password before starting the watchdog."
fi

echo ""
echo "Instance bootstrap complete."
echo "  Instance dir: ${INSTANCE_DIR}"
echo ""
echo "Next: ensure ops/watchdog/appsettings.yml.example's UpdateType: Manifest"
echo "      block is in /opt/ss14-watchdog/appsettings.yml, then"
echo "      'systemctl start ss14-watchdog'. The watchdog will download the"
echo "      latest build from https://ss14.zig.computer/cdn/ on first run."
