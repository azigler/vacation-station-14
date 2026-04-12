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

## Watchdog (SS14.Watchdog / "Ian")

SS14.Watchdog supervises `Robust.Server` as a child process: handles auto-
updates, restarts on crash, exposes an admin HTTP API for operator
actions (restart, shutdown, stats). Required for Level 4+ hosting.

Upstream: <https://github.com/space-wizards/SS14.Watchdog>.

### Install

One-shot build + install from the repo root:

```bash
sudo ./setup.watchdog.sh                      # build from master
sudo WATCHDOG_REF=v1.2.3 ./setup.watchdog.sh  # pin a tag or commit
```

The script is idempotent. It will:

- Create a system user `ss14:ss14` (no shell, home `/opt/ss14-watchdog`)
- Clone `SS14.Watchdog` into `/var/tmp/ss14-watchdog-build` and publish
  with **exactly** `dotnet publish -c Release -r linux-x64 --no-self-contained`
  (any deviation — self-contained, different RID — breaks execute bits
  on `Mono.Posix.NETStandard.dll`'s native helpers)
- rsync the publish output to `/opt/ss14-watchdog/`, preserving
  `appsettings.yml`, `instances/`, and `logs/`
- `chmod +x /opt/ss14-watchdog/SS14.Watchdog`
- Generate a fresh `ApiToken` via `openssl rand -hex 32` **only** if
  `appsettings.yml` doesn't already exist (re-runs leave it alone)
- Install `ops/watchdog/ss14-watchdog.service` to `/etc/systemd/system/`,
  `systemctl daemon-reload`, and `systemctl enable` — but **not** start

Pin `WATCHDOG_REF` in production so a drive-by upstream master push
doesn't trip a redeploy. Bump it deliberately.

Prereqs: .NET 10 SDK + ASP.NET Core 10 Runtime (installed by
`setup.ubuntu.sh --server`), `git`, `rsync`, `openssl`.

### Systemd unit semantics

`ops/watchdog/ss14-watchdog.service` is tuned for persistent game-server
children:

- **`KillMode=process`** — required when `Process.PersistServers: true`
  in `appsettings.yml`. The default (`control-group`) makes systemd kill
  every process in the cgroup on stop/reload, which defeats persistence.
  With `process`, only the watchdog PID gets the signal; the
  `Robust.Server` children are left running and the next watchdog reclaims
  them.
- **`OOMPolicy=continue`** — if a game-server child trips the kernel OOM
  killer, don't let systemd take the watchdog down with it. The watchdog
  will notice the child is gone and respawn it.
- **`Environment="DOTNET_CLI_HOME=/tmp"`** — .NET wants a writable home
  dir for CLI telemetry and lockfiles; `ss14`'s actual home is the
  install dir and we don't want .NET scribbling there.
- **`User=ss14` / `Group=ss14`** — the `setup.watchdog.sh` script creates
  this system user on first run. The watchdog (and therefore the game
  server) runs unprivileged. It does NOT need to bind low ports (the
  admin API is on 5000, game on 1212).
- **`Restart=on-failure`** + `RestartSec=5` — systemd will respawn the
  watchdog itself if it crashes, with a 5s backoff.
- **`After=network-online.target postgresql.service`** — game server
  migrations hit Postgres on boot, so start order matters on the same
  host.

### appsettings.yml

Template: `ops/watchdog/appsettings.yml.example` (installed to
`/opt/ss14-watchdog/appsettings.yml` on first setup run).

- **`ApiToken`** — generated automatically by `setup.watchdog.sh` on
  first install. The script prints it **once**; store it in your password
  manager immediately. Never commit the populated `appsettings.yml` —
  treat it like the postgres password.
- **`BaseUrl` / `Urls`** — default to localhost-only (`127.0.0.1:5000`).
  To control the watchdog from a remote operator box, front it with
  Caddy (see `docs/NETWORKING.md`) + HTTP basic auth or client certs, or
  SSH-tunnel `localhost:5000`. Do not bind the admin API to a public
  interface without a proxy + TLS.
- **Serilog** — Console sink lands in `journalctl -u ss14-watchdog`;
  File sink rolls daily to `/var/log/ss14-watchdog/watchdog-*.log` with
  14-day retention. The Loki sink is pre-wired but commented — enable
  it once **vs-2p3** (log aggregation bead) lands.
- **`Process.PersistServers: true`** — keeps game servers running across
  watchdog reloads. Pairs with `KillMode=process`.
- **`Notification.DiscordWebhook`** — uncomment and set to get crash /
  restart alerts in a Discord channel. Store the webhook URL in your
  password manager; it's effectively a secret.

Rotate the `ApiToken` by editing `appsettings.yml`, restarting the unit,
and updating the password-manager entry. No game-server downtime is
needed beyond the watchdog restart (children persist).

### Instance data layout

Each game-server instance lives under
`/opt/ss14-watchdog/instances/<name>/`. For us that's just
`vacation-station`:

```
/opt/ss14-watchdog/
├── SS14.Watchdog               # published binary
├── appsettings.yml             # watchdog config (secrets — not in git)
├── instances/
│   └── vacation-station/
│       ├── config.toml         # game-server config (secrets — not in git)
│       └── binaries/           # Local provider drop target
└── logs/                       # watchdog-managed runtime logs
```

Bootstrap the layout with:

```bash
sudo ./ops/watchdog/instance-bootstrap.sh
```

This creates the directories, then seeds `config.toml` from
`instances/vacation-station/config.toml.example` (if not already
present). Re-running does **not** clobber an existing `config.toml`.

After bootstrap, fill in the Postgres password in
`/opt/ss14-watchdog/instances/vacation-station/config.toml` and drop a
published `Robust.Server` build into the `binaries/` directory.

### First-run verification

```bash
# Unit is running
systemctl is-active ss14-watchdog             # → active
journalctl -u ss14-watchdog -n 100 --no-pager

# Game server is a child of the watchdog
pstree -p "$(systemctl show -p MainPID --value ss14-watchdog)"

# Admin API reachable on localhost only
curl -sSf http://localhost:5000/instances/vacation-station/status

# API auth test (replace TOKEN with the value from setup.watchdog.sh)
curl -sSf -H "WatchdogToken: ${TOKEN}" \
    -X POST http://localhost:5000/instances/vacation-station/restart

# Crash-recovery smoke test (the child should respawn within TimeoutSeconds)
sudo pkill -f Robust.Server
sleep 10
pstree -p "$(systemctl show -p MainPID --value ss14-watchdog)"   # child back
```

### Firewall

- **Port 5000 (watchdog admin API)** — localhost only by default. If you
  front with Caddy for remote admin, open `80/tcp` + `443/tcp` and let
  Caddy terminate TLS; do **not** open 5000 to the public internet.
- **Port 1212 (UDP + TCP)** — game netcode + status API, must be public.
  See `docs/NETWORKING.md` for the full UFW + cloud-firewall procedure.

### Update providers

We ship with `UpdateType: Local` to avoid a CDN dependency on day 1.
Operator publishes builds manually into
`/opt/ss14-watchdog/instances/vacation-station/binaries/`, then restarts
the instance via the admin API (or `systemctl restart ss14-watchdog`).

Once we stand up a build/publish pipeline (Robust.Cdn + object storage),
migrate to `UpdateType: Manifest`:

1. Stop publishing into `binaries/` — the Manifest provider downloads
   into its own versioned directory.
2. In `appsettings.yml`, flip the instance's `UpdateType` to `Manifest`
   and add an `Updates.ManifestUrl` pointing at the CDN.
3. Restart the watchdog. It will fetch the latest manifest, verify
   hashes, and start the server from the downloaded build.
4. Tear out the `Local` `binaries/` drop target once Manifest has been
   driving restarts cleanly for a release cycle.

Track the CDN/Manifest work as a separate bead.

### Log aggregation (vs-2p3)

The Loki Serilog sink in `appsettings.yml.example` is commented with a
TODO referencing bead **vs-2p3**. When that bead lands the Loki stack
on the host, uncomment the sink block and restart the watchdog — no
other config changes needed.
