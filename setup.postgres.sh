#!/bin/bash
# Vacation Station 14 — PostgreSQL install + role/DB provisioning
#
# Usage:
#   sudo ./setup.postgres.sh                      # installs PG 16, creates role+db, generates password
#   sudo PG_PASSWORD='...' ./setup.postgres.sh    # use a pre-chosen password (e.g. from password manager)
#
# Idempotent — safe to re-run. Existing roles/databases are left alone
# (password is NOT rotated on re-run; use the rotation procedure in
# docs/OPERATIONS.md for that).
#
# Tested on Ubuntu 24.04 LTS.

set -euo pipefail

# Default to 17 (matches dev flake pin + Ubuntu 25.10 native).
# Override with PG_VERSION env var for older distros (Ubuntu 22.04 → 14 or 16, 24.04 → 16).
PG_VERSION="${PG_VERSION:-17}"
PG_ROLE="vs14"
PG_DB="vacation_station"

# --- Preflight ---

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: must run as root (sudo)." >&2
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "Error: apt-get not found. This script is for Debian/Ubuntu." >&2
    exit 1
fi

# --- Install PostgreSQL 16 ---

echo ">>> Installing postgresql-${PG_VERSION}..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    "postgresql-${PG_VERSION}" \
    openssl

echo ">>> Enabling + starting postgresql service..."
systemctl enable --now postgresql

# --- Resolve password ---

GENERATED_PASSWORD=""
if [ -z "${PG_PASSWORD:-}" ]; then
    PG_PASSWORD="$(openssl rand -base64 32 | tr -d '\n')"
    GENERATED_PASSWORD="yes"
fi

# --- Create role (idempotent) ---

echo ">>> Ensuring role '${PG_ROLE}' exists..."
# Escape single quotes in password for SQL literal.
ESCAPED_PASSWORD="${PG_PASSWORD//\'/\'\'}"

# Use psql -v to pass values safely, avoiding interpolation of $ into SQL.
sudo -u postgres psql -v ON_ERROR_STOP=1 \
    -v role="${PG_ROLE}" \
    -v password="${ESCAPED_PASSWORD}" <<'SQL'
DO $do$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'role') THEN
        EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', :'role', :'password');
    END IF;
END
$do$;
SQL

# --- Create database (idempotent) ---

echo ">>> Ensuring database '${PG_DB}' exists (owned by '${PG_ROLE}')..."
DB_EXISTS="$(sudo -u postgres psql -tAc \
    "SELECT 1 FROM pg_database WHERE datname = '${PG_DB}'")"
if [ "${DB_EXISTS}" != "1" ]; then
    sudo -u postgres createdb --owner="${PG_ROLE}" "${PG_DB}"
else
    echo "    (database already exists, leaving alone)"
fi

# --- Summary ---

echo ""
echo "==============================================="
echo "  PostgreSQL ${PG_VERSION} setup complete"
echo "==============================================="
echo "  Role:     ${PG_ROLE}"
echo "  Database: ${PG_DB}"
echo "  Listen:   localhost:5432 (default pg_hba: local + host 127.0.0.1/::1)"
echo ""

if [ -n "${GENERATED_PASSWORD}" ]; then
    echo ">>> Generated password for role '${PG_ROLE}':"
    echo ""
    echo "    ${PG_PASSWORD}"
    echo ""
    echo "    STORE THIS IN YOUR PASSWORD MANAGER NOW."
    echo "    It will not be shown again. Re-running this script will NOT"
    echo "    rotate the password; see docs/OPERATIONS.md for rotation."
    echo ""
fi

echo ">>> Verify connectivity:"
echo "    PGPASSWORD='<password>' psql -h localhost -U ${PG_ROLE} -d ${PG_DB} -c 'select 1'"
echo ""
echo ">>> Next: wire the password into instances/vacation-station/config.toml"
echo "    (see instances/vacation-station/config.toml.example)"
