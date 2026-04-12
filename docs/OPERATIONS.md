# Operations

Runbooks for Vacation Station 14 production hosts (Level 4/5, per
`docs/HOSTING.md`). Commands assume Ubuntu 24.04 LTS and a repo deployed
to `/opt/vacation-station`.

## PostgreSQL

Vacation Station 14 uses PostgreSQL from day 1 instead of the default
SQLite. SS14.Admin requires it, and starting production-shaped avoids
a painful migration later.

### Install

One-shot bootstrap from the repo root:

```bash
sudo ./setup.postgres.sh
```

The script is idempotent. It will:

- `apt install postgresql-16` and `systemctl enable --now postgresql`
- Create role `vs14` with a password (generated via `openssl rand -base64 32`
  if `$PG_PASSWORD` is unset; otherwise the value from the environment)
- Create database `vacation_station`, owned by `vs14`
- Print the generated password **once** — store it in your password manager
  immediately. Re-running the script does NOT rotate the password.

Verify:

```bash
PGPASSWORD='<password>' psql -h localhost -U vs14 -d vacation_station -c 'select 1'
```

### User / database semantics

- `vs14` is the only application role. It `LOGIN`s and `OWNS`
  `vacation_station`. No superuser rights.
- SS14 runs schema migrations on every server start. The DB starts empty;
  on first boot the server populates the schema. Check the server log for
  `Applied N migration(s)` or similar and then:

  ```bash
  sudo -u postgres psql -d vacation_station -c '\dt'
  ```

- Never hand-edit schema. Migrations are source-of-truth.

### Config wiring

Copy the template and fill in the password:

```bash
cp instances/vacation-station/config.toml.example \
   instances/vacation-station/config.toml
$EDITOR instances/vacation-station/config.toml   # replace pg_password
```

Only `config.toml.example` is tracked in git. `config.toml` holds secrets
and must stay local — `.gitignore` should cover it (see repo root).

### Access control (pg_hba.conf)

Ubuntu's default `pg_hba.conf` for PostgreSQL 16 allows:

- `local` (Unix socket, peer auth) — for `postgres` admin user
- `host ... 127.0.0.1/32` and `::1/128` (md5/scram) — for `vs14`

That is correct for our deployment: the SS14 server runs on the same host
and connects to `localhost:5432`. Do **not** expand `listen_addresses` or
`pg_hba.conf` to non-loopback without a firewall in front. If we ever
need to expose Postgres (e.g. a separate SS14.Admin host), plan a
`host all vs14 10.x.x.x/32 scram-sha-256` rule, a dedicated network, and
a firewall review — flag it as a new bead.

### Backups

`ops/postgres/backup.sh` produces a `pg_dump -Fc` to
`/var/backups/vacation-station/`. Retention: 7 daily + 4 weekly. Weekly
dumps (Sunday) are tagged separately so the weekly cohort survives daily
pruning.

Install the systemd units:

```bash
sudo install -m0644 ops/postgres/ss14-backup.service  /etc/systemd/system/
sudo install -m0644 ops/postgres/ss14-backup.timer    /etc/systemd/system/
sudo mkdir -p /var/backups/vacation-station
sudo chown postgres:postgres /var/backups/vacation-station
sudo systemctl daemon-reload
sudo systemctl enable --now ss14-backup.timer
```

Check status:

```bash
systemctl list-timers ss14-backup.timer
journalctl -u ss14-backup.service --since '1 day ago'
ls -lh /var/backups/vacation-station/
```

#### Manual backup

```bash
sudo -u postgres /opt/vacation-station/ops/postgres/backup.sh
```

#### Restore

Full restore into a fresh database (drops existing schema — stop the
SS14 server first):

```bash
# Stop the game server so no connections hold locks.
sudo systemctl stop ss14-watchdog    # or whatever supervises Robust.Server

# Recreate the target DB owned by vs14.
sudo -u postgres dropdb vacation_station
sudo -u postgres createdb --owner=vs14 vacation_station

# Restore. -C is omitted here because we recreated the DB explicitly;
# -d vacation_station targets it directly.
sudo -u postgres pg_restore --no-owner --role=vs14 \
    -d vacation_station \
    /var/backups/vacation-station/daily-vacation_station-<ts>.dump

sudo systemctl start ss14-watchdog
```

Alternatively, `pg_restore -C -d postgres <dump>` will recreate the DB
from the dump's metadata in one step — useful for restoring to a fresh
host.

Always verify the sha256 sidecar before restoring:

```bash
cd /var/backups/vacation-station && sha256sum -c <dump>.sha256
```

### Credential rotation

Passwords are not rotated by `setup.postgres.sh` on re-run. To rotate:

1. Generate a new password: `openssl rand -base64 32`
2. Apply to the role:
   ```bash
   sudo -u postgres psql -c "ALTER ROLE vs14 WITH PASSWORD '<new>';"
   ```
3. Update `instances/vacation-station/config.toml` `pg_password`
4. Restart the SS14 server (watchdog will reconnect)
5. Update the password manager entry; invalidate the old value

No downtime is required beyond the server restart.

### Connection pooling

Postgres `max_connections` defaults to 100, which is plenty for a single
SS14 instance (typical usage is well under 10 concurrent connections:
one from the game server, a few from SS14.Admin, occasional ops psql).

We are **not** running PgBouncer initially. Revisit if:

- We run multiple SS14 instances against one DB
- SS14.Admin + Robust.Cdn + metrics collectors push sustained connections
  past ~50
- We need transaction-pooling latency wins

### Future: offsite backups

Local-disk retention protects against SS14 bugs and operator mistakes but
not host loss. Planned migration path (track as a separate bead):

- Mirror `/var/backups/vacation-station/` to S3-compatible object storage
  (Backblaze B2, Cloudflare R2, Hetzner Object Storage) via `rclone sync`
  in a second systemd timer that runs after `ss14-backup.service`
- Lifecycle policy on the bucket for longer-term retention (e.g. 90 days
  of dailies, 12 months of weeklies)
- Separate credentials scoped to the backup bucket only
- Periodic restore drills against a scratch host

Keep the local retention when we add offsite — belt and suspenders.
