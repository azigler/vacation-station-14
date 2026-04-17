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

The Loki Serilog sink in `appsettings.yml.example` is wired to push watchdog
logs at `http://localhost:3100` — the Loki container deployed in
`ops/observability/`. The game server does the same via its `[loki]` block
in `config.toml`. See the "Observability" section below for bring-up.

## Cookbook

[arimah/ss14-cookbook](https://github.com/arimah/ss14-cookbook) is a static
recipe + crafting reference site that parses SS14 prototypes directly from a
repo clone. Vacation Station 14 vendors it as a submodule and serves the
generated static files at
[`https://ss14.zig.computer/recipes/`](https://ss14.zig.computer/recipes/).

### What's on disk

| Path | Role |
|---|---|
| `external/cookbook/` | Submodule pinning arimah/ss14-cookbook (pristine; never edited in place) |
| `ops/cookbook/sources.yml` | VS14 fork config (points at the sibling clone) |
| `ops/cookbook/privacy.html` | Privacy notice embedded into the built site |
| `ops/cookbook/rewrites_vacation.yml` | VS14-specific recipe ID rewrites (empty by default) |
| `ops/cookbook/build.sh` | Clone/pull sibling, `npm ci`, build, rsync to web root |
| `ops/cookbook/vs14-cookbook-build.service` + `.timer` | Daily (05:00 UTC) rebuild |
| `ops/cookbook/install.sh` | One-shot host installer (units + writable roots + timer enable) |
| `/var/lib/vs14-cookbook-source/` | Sibling read-only VS14 clone `build.sh` maintains |
| `/var/www/vs14-recipes/` | Static output; nginx `/recipes/` alias target |

The cookbook needs raw YAML + PNG files (not compiled output), which is why
`build.sh` maintains a dedicated sibling clone at
`/var/lib/vs14-cookbook-source/` instead of pointing at the deploy checkout.

### Install

Assumes the repo is deployed at `/opt/vacation-station` and the `ss14` user
exists (see "Watchdog" above), plus Node.js + npm on PATH.

```bash
sudo ./ops/cookbook/install.sh
```

The script is idempotent:

- Installs `vs14-cookbook-build.{service,timer}` into `/etc/systemd/system/`
- Creates `/var/www/vs14-recipes/` and `/var/lib/vs14-cookbook-source/` owned
  by `ss14:ss14`
- `systemctl daemon-reload` + `enable --now vs14-cookbook-build.timer`

The timer fires daily at 05:00 UTC (offset from the 03:15 UTC backup timer so
the two don't fight for disk).

### Force a rebuild

```bash
sudo systemctl start vs14-cookbook-build.service
journalctl -u vs14-cookbook-build.service -f
```

The service is `Type=oneshot`; the command returns when the build finishes.
Typical runtime is a few minutes (mostly `npm ci` + thousands of YAML files).

### AGPLv3 compliance — "View Source" link

The cookbook template renders a footer link out of the `COOKBOOK_REPO_URL`
env var. `build.sh` writes `external/cookbook/.env` on every run with
`COOKBOOK_REPO_URL=https://github.com/azigler/vacation-station-14`, so the
deployed footer points at our repo with no post-build patching. If the
upstream template ever drops that env hook, we'd switch to a post-build
patch step inside `build.sh` and promote the cookbook to a forked service
(see the "promotion triggers" on bead vs-1vy).

### Logs

```bash
journalctl -u vs14-cookbook-build.service --since '2 days ago'
systemctl list-timers vs14-cookbook-build.timer
```

### Troubleshooting

- **Build fails at `npm ci`** — check Node + npm are on PATH for the `ss14`
  user; the service inherits the ambient system PATH. `sudo -u ss14 which node`
  from the install host.
- **Recipes missing after a merge** — the sibling clone auto-resets to
  `origin/main` each run. If `main` hasn't been pushed yet, the cookbook is
  parsing stale data. Push, then kick the service.
- **A recipe doesn't render / sorts oddly** — add an entry to
  `ops/cookbook/rewrites_vacation.yml` (format: `RecipeID: ReplacementEntityID`)
  and commit. The next build picks it up.
- **`alias` returns 404** — nginx wants `/var/www/vs14-recipes/index.html` to
  exist. If the build has never run, `install.sh` created the empty dir but
  nothing inside it. Kick the service once to populate.

## Observability

Vacation Station 14 ships a self-hosted Prometheus + Loki + Grafana stack in
`ops/observability/`, co-located with the game server. Metrics come from
Robust.Server's native Prometheus endpoint on `localhost:44880`; logs come
from the server and watchdog via Serilog's Loki sink. Grafana provides the
UI and is fronted by Caddy for HTTPS.

Dashboards are auto-provisioned from `ops/observability/grafana/dashboards/`
(see the "Dashboards" subsection below). Alerting is explicitly out of scope.

### Layout

```
ops/observability/
├── docker-compose.yml              # prometheus + loki + grafana
├── prometheus.yml                  # scrape config (job=gameservers)
├── loki-config.yml                 # single-binary, 30d retention
├── .env.example                    # POSTGRES_PASSWORD — copy to .env
├── secrets/                        # grafana_admin_password.txt lives here
└── grafana/
    ├── provisioning/datasources/   # prometheus, loki, postgres
    ├── provisioning/dashboards/    # file provider
    └── dashboards/                 # JSON drops (populated by vs-13x)
```

### Bootstrap secrets

Both files are gitignored. Generate them before first `up`:

```bash
# Grafana admin password — sourced from a docker secret.
mkdir -p ops/observability/secrets
openssl rand -base64 32 > ops/observability/secrets/grafana_admin_password.txt
chmod 600 ops/observability/secrets/grafana_admin_password.txt

# Grafana Postgres datasource password — must match the vs14 role's
# password from setup.postgres.sh. Pull the value from your password
# manager; the .env file is a local-only cache.
cp ops/observability/.env.example ops/observability/.env
$EDITOR ops/observability/.env   # set POSTGRES_PASSWORD=
chmod 600 ops/observability/.env
```

Store both secrets in your password manager. Do not commit the populated
files; the directory's `.gitignore` guards against accidents.

### Bring-up

```bash
cd ops/observability
docker compose up -d
docker compose ps           # all three should be "running (healthy)"
```

`docker compose config` parses the stack without starting anything, handy
for validating edits.

First boot pulls images (~600 MB total) and installs the
`grafana-postgresql-datasource` plugin into Grafana. Subsequent restarts
are seconds.

### First-run verification

Prometheus scrape target is UP:

```bash
curl -s http://localhost:9090/-/ready
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health}'
# → gameservers / up
```

Sample metrics query (once the SS14 server is running):

```bash
curl -sG http://localhost:9090/api/v1/query \
    --data-urlencode 'query=robust_player_count{server="vacation-station"}'
```

Loki is ready:

```bash
curl -s http://localhost:3100/ready    # → ready
```

Sample Loki query (LogQL):

```
{App="Robust.Server",Server="vacation-station"}
```

Grafana login:

```bash
xdg-open http://localhost:3200        # or reach via Caddy HTTPS
# User: admin
# Password: contents of ops/observability/secrets/grafana_admin_password.txt
```

Change the password on first login. The datasources and dashboard provider
are already provisioned; confirm via *Connections → Data sources*.

### Wiring the game server and watchdog

The config templates are already set up — you only need to make sure the
instance configs mirror them:

- `instances/vacation-station/config.toml` has `[metrics]` (port 44880) and
  `[loki]` (address `http://localhost:3100`, name `vacation-station`).
- `/opt/ss14-watchdog/appsettings.yml`'s Serilog `WriteTo` list includes
  `GrafanaLoki` pointing at `http://localhost:3100`.

After editing either config, restart the affected unit:

```bash
sudo systemctl restart ss14-watchdog
```

### Network topology

All three services sit on an internal Docker bridge network (`observability`).
On the host, only `127.0.0.1` is bound:

| Service    | Host bind          | Purpose                             |
|------------|--------------------|-------------------------------------|
| Prometheus | `127.0.0.1:9090`   | Operator-only debug UI              |
| Loki       | `127.0.0.1:3100`   | SS14 server + watchdog push         |
| Grafana    | `127.0.0.1:3200`   | Dashboards; fronted by Caddy + TLS  |

Prometheus reaches the SS14 metrics endpoint via `host.docker.internal`, the
Docker host-gateway alias — the container sees the host as a regular
hostname. `docker-compose.yml` wires this with `extra_hosts`.

Firewall: nothing new is public. Grafana only reaches the outside world via
the Caddy reverse proxy below, which terminates TLS on 443. Prometheus,
Loki, and Grafana's direct ports do NOT need to be opened in ufw or the
cloud firewall. See `docs/NETWORKING.md` for the full firewall recipe.

### Caddy reverse-proxy snippet

Add to `/etc/caddy/Caddyfile` (and reload Caddy):

```
grafana.yourdomain.com {
    reverse_proxy 127.0.0.1:3200
}
```

Caddy's automatic Let's Encrypt flow takes care of TLS. Point a DNS `A`
record at the host, ensure 80/tcp and 443/tcp are open (ACME HTTP-01), and
log in to Grafana over HTTPS.

### Retention

- **Prometheus**: 15 days (default, set via `--storage.tsdb.retention.time`
  in `docker-compose.yml`). Raise by editing the flag; storage cost is
  roughly linear.
- **Loki**: 30 days, enforced by the compactor (`retention_period: 720h`
  in `loki-config.yml`). The compactor runs every 10 minutes and deletes
  chunks older than the retention window.

Both datasets live in named Docker volumes (`prometheus-data`, `loki-data`,
`grafana-data`), which survive container rebuilds. `docker volume ls` and
`docker volume inspect <name>` show the mount path on the host.

### Rotating the Grafana admin password

```bash
openssl rand -base64 32 > ops/observability/secrets/grafana_admin_password.txt
cd ops/observability && docker compose restart grafana
```

Grafana re-reads the secret file on startup. Update the password manager
entry afterwards.

### Troubleshooting

**Prometheus target `gameservers` is DOWN**
- Confirm the SS14 server is running and `[metrics] enabled = true` is set
  in `config.toml`.
- From the host: `curl -s localhost:44880/metrics | head` should return
  Prometheus exposition text.
- From the prometheus container: `docker compose exec prometheus wget -qO-
  http://host.docker.internal:44880/metrics | head`. If that fails, the
  `host.docker.internal` alias isn't resolving — check `extra_hosts` in
  `docker-compose.yml`.
- ufw or the cloud firewall blocking 44880 on the loopback is rare but
  possible; loopback traffic should never hit a firewall unless a rule
  explicitly targets `lo`.

**No logs in Loki**
- Confirm the game server's `[loki]` block is enabled and `address` points
  at `http://localhost:3100` (not `https`, not the container name).
- Confirm the watchdog's `appsettings.yml` includes the `GrafanaLoki` sink
  (uncommented) and the unit has been restarted since the edit.
- `curl -s localhost:3100/ready` must return `ready`.
- From Grafana's Explore view, run `{App="Robust.Server"}` with no other
  filter and widen the time range — the `Server` label may be different
  than expected if the config's `name` doesn't match.

**Grafana can't reach Postgres datasource**
- The `$POSTGRES_PASSWORD` env var is missing or wrong; check
  `ops/observability/.env`.
- The vs14 role's password changed but `.env` was not updated.
- Postgres is bound to the wrong interface; `setup.postgres.sh` binds to
  `localhost`, and the Grafana container uses `host.docker.internal` to
  reach it — verify with
  `docker compose exec grafana getent hosts host.docker.internal`.

**Grafana login fails**
- The admin password is whatever is in
  `ops/observability/secrets/grafana_admin_password.txt`. If the file is
  missing, the container fails healthcheck and restarts in a loop.

### Dashboards

Two dashboards ship in-repo at `ops/observability/grafana/dashboards/`,
adapted from the upstream SS14 community exports:

| File                  | Dashboard UID         | Title                                 | Purpose                                                                 |
|-----------------------|-----------------------|---------------------------------------|-------------------------------------------------------------------------|
| `game-servers.json`   | `vs14-game-servers`   | Vacation Station - Game Servers       | Fleet overview: player count, tick time, CPU, round length, connections |
| `perf-metrics.json`   | `vs14-perf-metrics`   | Vacation Station - Perf Metrics       | Per-server deep-dive with a Loki logs panel and tick/entity histograms  |

**Upstream source** for future diffs:
<https://docs.spacestation14.com/en/community/infrastructure-reference/grafana-dashboards.html>
(rendered from `space-wizards/docs/src/en/community/infrastructure-reference/grafana-dashboards.md`).

#### Auto-provisioning

On Grafana startup, two mounts wire everything up:

```yaml
volumes:
  - ./grafana/provisioning:/etc/grafana/provisioning:ro
  - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
```

- `provisioning/datasources/datasources.yml` registers Prometheus, Loki, and
  Postgres under stable names. Dashboard JSONs reference those datasources
  by name (`"uid": "Prometheus"`, `"uid": "Loki"`, `"uid": "Postgres"`);
  Grafana resolves name-as-uid against the provisioned set.
- `provisioning/dashboards/dashboards.yml` runs the file provider against
  `/var/lib/grafana/dashboards`, polling every 30 s. Every `*.json` in that
  directory surfaces in the "Vacation Station" folder.

#### Updating a dashboard

```bash
# Edit the JSON (directly, or paste from a UI export — see below)
$EDITOR ops/observability/grafana/dashboards/game-servers.json
# File provider notices within 30 s; or force a re-scan:
cd ops/observability && docker compose restart grafana
```

The pinned `uid` fields (`vs14-game-servers`, `vs14-perf-metrics`) let
Grafana recognise the provisioned dashboard across restarts and apply
edits in-place rather than creating duplicates.

#### Customising or adding panels

The intended workflow for fork-specific changes:

1. In Grafana UI, clone the dashboard (Settings → Save As) and iterate
   against real data. The provisioned copies are marked read-only
   (`allowUiUpdates: false`), so your working copy becomes a separate
   dashboard with its own uid.
2. When the panel set is stable, export JSON via
   *Dashboard → Share → Export → Save to file*. Untick "Export for sharing
   externally" so datasource uids stay bound (to our provisioned names)
   rather than being templated back into `${DS_…}` inputs.
3. Copy the exported JSON over the provisioned file, restore the pinned
   `uid` + `title`, and commit. Run the JSON through `python -m json.tool`
   to keep the diff readable.
4. Net-new dashboards that are purely VS-original go in the same directory
   with a `vs14-<slug>` uid; no other wiring needed.

If you need to remove the upstream-derived panels entirely (e.g. to slim
down the fleet dashboard for a single-server deployment), delete the
relevant panel objects from the JSON — the file provider picks up the
shrunken dashboard on the next poll.

#### Known adaptation caveats

- The Game Servers dashboard's TPS alert retains the upstream notification
  channel uid (`N5nihcmMk`); Grafana will log a "missing notifier" warning
  until the alert is rewritten against a local contact point. Non-fatal.
- A handful of `byName` field-override matchers reference upstream server
  names (e.g. `wizards_den_eu_west`). These no-op in our single-instance
  deployment and are preserved verbatim as documentation of the upstream
  intent — safe to prune on the first UI-driven edit pass.
- The `$Server` template variable is rewritten to
  `label_values(ss14_round_length{job="gameservers"}, server)`, defaulting
  to `vacation-station` to match the label set in `prometheus.yml`.

## Maps (SS14.MapViewer)

The player-facing interactive map browser at
`https://ss14.zig.computer/maps/` is a static build of
[SS14.MapViewer][mv-upstream], populated by tiles rendered locally
via the `Content.MapRenderer` tool already in the repo. No backend,
no DB — just a nightly-ish (weekly, Sunday 04:30 UTC) rebuild timer
rsyncing a fresh bundle into the nginx serve root.

[mv-upstream]: https://github.com/space-wizards/SS14.MapViewer

### Layout

| Concern | Where |
|---|---|
| Upstream source (pinned) | `external/mapviewer/` (git submodule) |
| VS14-specific config + build glue | `ops/mapviewer/` |
| Systemd unit + timer | `ops/mapviewer/systemd/vs14-mapviewer-build.{service,timer}` |
| Scratch + staging | `/var/cache/vs14-mapviewer/` |
| nginx serve root | `/var/www/vs14-maps/` (aliased under `/maps/`) |
| Renderer entrypoint | `Content.MapRenderer/Content.MapRenderer.csproj` |

The pipeline is fully documented in
[`ops/mapviewer/README.md`](../ops/mapviewer/README.md); this section
is the OPERATIONS-level runbook.

### Install

```bash
cd /opt/vacation-station
git submodule update --init --recursive external/mapviewer

sudo install -d -o ss14 -g ss14 -m 0755 \
    /var/www/vs14-maps /var/cache/vs14-mapviewer

sudo cp ops/mapviewer/systemd/vs14-mapviewer-build.{service,timer} \
    /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now vs14-mapviewer-build.timer
```

The nginx `/maps/` location is already committed in
`ops/nginx/ss14.zig.computer.conf`; no vhost changes are needed to
enable MapViewer.

### Force-rebuild

Trigger an immediate bundle refresh (useful after a map merge, or
for an ad-hoc validation run):

```bash
sudo systemctl start vs14-mapviewer-build.service
sudo journalctl -u vs14-mapviewer-build.service -f
```

Expected runtime: ~3–8 minutes depending on map count and whether
`npm ci` can hit its cache. The old bundle keeps serving until the
final `rsync --delete-after` swaps it out, so a failed build does
not take the site down.

### Subset rebuild (manual)

For local debugging or when you only want to re-render a specific
map, run the build script with `MAP_LIST` set — it short-circuits
the auto-discovery step:

```bash
sudo -u ss14 MAP_LIST="box bagel saltern" \
    /opt/vacation-station/ops/mapviewer/build.sh
```

Other env overrides (see `ops/mapviewer/build.sh` header):
`OUTPUT_FORMAT=png`, `SKIP_NPM_INSTALL=1`, `SKIP_RENDER=1`,
`STAGE_DIR=/tmp/...`, `SERVE_ROOT=/tmp/...`.

### Troubleshooting

**`/maps/` returns the nginx "coming soon" stub.** The build has
never run successfully on this host. Check:
```bash
systemctl list-timers vs14-mapviewer-build.timer
sudo journalctl -u vs14-mapviewer-build.service -n 200
ls -la /var/www/vs14-maps/
```
If the serve root is empty, kick a manual build (see above).

**Map selector empty.** `Content.MapRenderer` ran but produced no
output. Inspect `/var/cache/vs14-mapviewer/rendered-maps/`; if the
subdirs aren't there, the renderer errored. Re-run with verbose
logging:
```bash
sudo -u ss14 dotnet run \
    --project /opt/vacation-station/Content.MapRenderer \
    -c Release -- --viewer --format webp --output /tmp/mr-test box
```

**Broken asset URLs in the browser (404 on `/maps/assets/...`).**
The Vite `--base=/maps/` flag in `build.sh` and the nginx
`location /maps/` must match. If we ever relocate the map viewer to
a different sub-path, update both in the same commit — see
`ops/mapviewer/README.md` for the split-knob warning.

**Disk creep.** The staging dir under `/var/cache/vs14-mapviewer/`
survives between runs (by design — npm + Vite caching). If disk gets
tight:
```bash
sudo rm -rf /var/cache/vs14-mapviewer/{bundle,mapviewer-dist,rendered-maps}
sudo -u ss14 /opt/vacation-station/external/mapviewer/node_modules  # keep or drop
```
Then re-run the service.

### Dynamic-rendering deferred

SS14.MapServer — the upstream webhook-driven render backend — is
explicitly **not** deployed. See the "Dynamic rendering (deferred)"
section of `ops/mapviewer/README.md` for the tradeoff and the
trigger conditions for revisiting. Until then, weekly static
rebuilds are the source of truth for rendered maps.

## CI Workflows

VS14 inherits its CI workflow set from upstream SS14 at the Phase 1
Flavor A reset. The post-reset audit (vs-1uk) classifies each workflow
by suitability for a solo + AI maintainer.

### Active — quality gates

| Workflow | Purpose |
|---|---|
| `build-test-debug.yml` | Compile + unit tests |
| `check-crlf.yml` | Line-ending sanity |
| `yaml-linter.yml` | Prototype YAML validation |
| `validate-rsis.yml` | RSI metadata integrity |
| `validate-rgas.yml` | RGA schema validation |
| `validate_mapfiles.yml` | Map file schema validation |
| `rsi-diff.yml` | PR-comment visual sprite diffs |
| `build-map-renderer.yml` | Map preview generation |
| `no-submodule-update.yml` | Block accidental RobustToolbox bumps |
| `test-packaging.yml` | Release packaging succeeds |

### Active — publishing

| Workflow | Purpose |
|---|---|
| `publish.yml` | Production release artifact |
| `publish-testing.yml` | Testing / beta builds |

### Active — PR bookkeeping

| Workflow | Purpose |
|---|---|
| `labeler-pr.yml` | Auto-apply type labels |
| `labeler-size.yml` | S/M/L/XL size labels |
| `labeler-conflict.yml` | Merge-conflict detection |
| `labeler-needsreview.yml` | Needs-review state |
| `labeler-untriaged.yml` | Default state |
| `labeler-stable.yml` / `labeler-staging.yml` | Branch channel tags (deferred — re-evaluate when we stand up channeled releases) |
| `close-master-pr.yml` | Auto-close wrong-branch PRs |
| `update-credits.yml` | Contributor list (repo-guarded; runs on fork as intended) |

### Disabled

Disabled via `gh workflow disable <id> -R azigler/vacation-station-14`.
Re-enable with `gh workflow enable`.

| Workflow | Why disabled |
|---|---|
| `benchmarks.yml` | SSHes to upstream Wizards Den centcomm; will never succeed on this fork. Custom bench infra is a separate scoped bead if needed. |
| `build-docfx.yml` | VS14 does not run a DocFX docs site; player docs planned through website (vs-352) instead. |
| `labeler-review.yml` | Requires a `LABELER_PAT` secret for cross-repo review-state updates; no benefit for a solo maintainer. |

### Planned (per vs-f0l)

- `pr-triage.yml` — scheduled PR classifier + summary comment
- `auto-merge.yml` — trusted-author auto-merge with CI + soak gate
- `pr-hygiene.yml` — advisory-only hygiene comments

### Planned (potential adoption)

- `prtitlecase.yml` from Einstein-Engines — PR title validation (low-risk; adopt if lightweight)
- `changelog.yml` / `publish-changelog.yml` from Frontier — paired with SS14.Changelog webhook (vs-3v4); decide when webhook infrastructure exists
- `discord-changelog.yml` — community announcement pipeline; paired with vs-2l2
## Automated PR handling

VS14 is maintained by one human plus AI assistance (see
[`.claude/skills/vibe-maintainer/SKILL.md`](../.claude/skills/vibe-maintainer/SKILL.md)),
so the bookkeeping portion of maintainer work is automated. Three GitHub
Actions workflows implement the policy documented in the
`/vibe-maintainer` skill and [`CONTRIBUTING.md`](../CONTRIBUTING.md).

The output is deliberately **machine-readable** (stable label names plus
a marker-tagged comment on every open PR) so the maintainer's agent can
pick up context in one fetch rather than N tool calls. Humans read the
same output; it is not a proprietary encoding.

### Workflow stack

| Workflow | File | Trigger | Purpose |
|---|---|---|---|
| PR Triage | `.github/workflows/pr-triage.yml` | `pull_request_target` + `schedule` (every 4h) + `workflow_dispatch` | Auto-close drafts, auto-close banned-author PRs, apply `auto-merge` for trusted-bot XS/green PRs, post the `<!-- vs14-triage-summary -->` comment. |
| PR Auto-merge | `.github/workflows/auto-merge.yml` | `pull_request_target` (label changes) + `workflow_run` (CI completes) + `schedule` (every 30min safety net) | Squash-merges PRs that carry `auto-merge`, pass all gates, and have soaked for `AUTO_MERGE_SOAK_HOURS`. Strips the label and comments if CI turns red mid-soak. |
| PR Hygiene | `.github/workflows/pr-hygiene.yml` | `pull_request_target` (opened / synchronize / reopened / ready_for_review) | Advisory-only. Comments on multi-theme PRs and on player-facing PRs missing a `:cl:` block. Never blocks. |

Shared helpers live under `.github/workflows/scripts/` (bash; use `gh`
CLI plus `jq`/`yq`). They are shellcheck-clean (`shellcheck -S warning`)
and intended to be reusable from a `workflow_dispatch` run if you need
to re-triage by hand.

### Trust configuration

Author trust is data, not code:

- `.github/trusted-authors.yml`
  - `bots:` -- automatic `auto-merge` label on XS / green PRs. Seeded
    with `dependabot[bot]` and `renovate[bot]`.
  - `humans:` -- humans who have demonstrated a sustained record of
    clean, well-scoped PRs. Start empty and grow **organically**. A
    "human-trusted" author is not auto-merged; they get an `easy-win`
    categorization hint in the triage summary.
- `.github/banned-authors.yml`
  - `users:` -- logins whose PRs are immediately closed with a polite
    template. Use rarely; default posture is absorb-by-default.

**To add a human to `trusted-authors.yml`:**

1. Confirm at least ~5 merged PRs with no maintainer rework.
2. Open a PR editing `.github/trusted-authors.yml` only -- add the
   login under `humans:`. Keep the change small (size-XS) so it can
   soak and auto-merge if you like your own dogfood.
3. Note the promotion in the PR body; no ceremony required.

**To ban an author:**

Edit `banned-authors.yml` directly and land a commit. The next triage
sweep (cron every 4h, or `workflow_dispatch`) closes their open PRs.

### Tuning the soak timer

Auto-merge will not merge before `AUTO_MERGE_SOAK_HOURS` (default `12`)
has elapsed since the label was applied. The timer exists to give the
human maintainer a window to intervene -- tighten it when you trust the
pipeline; loosen it when you do not.

To change it, edit the `env:` block in `.github/workflows/auto-merge.yml`:

```yaml
env:
  AUTO_MERGE_SOAK_HOURS: "12"   # lower = faster auto-merge
  AUTO_MERGE_LABEL: "auto-merge"
  AUTO_MERGE_BLOCKLIST: "needsreview,S: Needs Review,do-not-merge,status/blocked"
```

Other tuning knobs live in the same block: the block-list lets you
rename / extend the labels that veto auto-merge without rewriting the
script.

### Triage summary format

The triage-summary comment is tagged with an HTML marker and a
markdown table. Downstream parsers (see
`.claude/skills/vibe-maintainer/SKILL.md`) key off the marker plus the
`| key | value |` table schema; keep those stable when editing:

```markdown
<!-- vs14-triage-summary -->
## Triage summary

| key | value |
|-----|-------|
| author | `dependabot[bot]` |
| trusted-bot | `true` |
| size-bucket | `XS` |
| ci-state | `green` |
| category | `easy-win` |
| auto-merge-eligible | `true` |
...
```

The `category` field is always one of `easy-win`,
`fix-merge-candidate`, or `needs-deeper-look` -- matching the tiers in
the `/vibe-maintainer` skill.

### Discord notifications (deferred)

`.github/workflows/auto-merge.yml` contains a commented-out Discord
notification step. It is gated on the `DISCORD_OPS_WEBHOOK` repo secret
and pairs with bead **vs-2l2** (Discord ops integration). To enable:

1. Provision the webhook in the ops Discord channel.
2. Add the URL to the repo as secret `DISCORD_OPS_WEBHOOK`.
3. Uncomment the `Notify Discord on merge` step in
   `auto-merge.yml`.

The auto-merge eval script writes merged PR numbers to
`$GITHUB_WORKSPACE/.auto-merged` during the run; the notification step
reads that file so a single run can announce a batch of merges.

### Manual override

- **Force re-triage:** `gh workflow run "PR Triage"` (the
  `workflow_dispatch` trigger sweeps all open PRs).
- **Force auto-merge evaluation:** `gh workflow run "PR Auto-merge"`.
- **Skip auto-merge on a PR:** remove the `auto-merge` label, or add
  any label in `AUTO_MERGE_BLOCKLIST` (e.g. `do-not-merge`).
- **Bypass soak window:** either lower `AUTO_MERGE_SOAK_HOURS`
  temporarily, or merge by hand via `gh pr merge --squash`.

## SS14.Admin

The [SS14.Admin](https://github.com/space-wizards/SS14.Admin) web admin panel
is bundled as-is per the vs-19h decision matrix. The submodule lives at
`external/ss14-admin/` and is deployed via docker-compose from
`ops/ss14-admin/`. nginx fronts it at `https://ss14.zig.computer/admin/`.

### Layout

```
ops/ss14-admin/
├── docker-compose.yml                  # host-networked; loopback 127.0.0.1:5427
├── appsettings.Production.yaml.example # committed template; real copy gitignored
├── .env.example                        # POSTGRES_PASSWORD — copy to .env
├── install.sh                          # idempotent bring-up
└── ss14-admin.service                  # optional systemd wrapper
```

### Secrets

Two env files feed the container. Neither is in the repo.

- `/etc/vacation-station/admin-oauth.env` (root:ss14, mode 640). Holds
  `OIDC_CLIENT_ID` and `OIDC_CLIENT_SECRET` registered via Wizden's
  self-service portal. Rotate via the portal + `docker compose restart
  ss14-admin`; the secret transited a Claude chat transcript during
  initial deploy and should be rotated post-cutover as a matter of
  hygiene.
- `/etc/vacation-station/admin-db.env` (mode 640 root:ss14). Holds
  `POSTGRES_PASSWORD`, same value as `ops/observability/.env` (both
  consume the `vs14` role). Kept alongside `admin-oauth.env` in
  `/etc/vacation-station/` so the compose file is clone-agnostic —
  works identically from `/home/` and `/opt/` clones (vs-2f8.5).

docker-compose maps `OIDC_CLIENT_ID` → `Auth__ClientId` and
`OIDC_CLIENT_SECRET` → `Auth__ClientSecret` via the `environment:` block;
the YAML appsettings file holds only placeholders and is safe to commit.

### Bring-up

```bash
# One-time, on the host:
sudo install -m 0640 -o root -g ss14 admin-oauth.env \
    /etc/vacation-station/admin-oauth.env        # creds from Wizden
sudo install -m 0640 -o root -g ss14 /dev/null \
    /etc/vacation-station/admin-db.env           # create empty, perms 640
sudoedit /etc/vacation-station/admin-db.env      # add POSTGRES_PASSWORD=

# Bring the stack up (idempotent). Run from the prod clone:
cd /opt/vacation-station && sudo ./ops/ss14-admin/install.sh

# Publish the nginx location block:
sudo ./ops/nginx/install.sh
```

Smoke test:

```bash
curl -sSI https://ss14.zig.computer/admin/ | head -5
# Expected: 302 to central.spacestation14.io/web/... (OIDC redirect)
```

### Database

SS14.Admin extends the game server's `vacation_station` database in place;
no separate DB is provisioned. Migrations run on first startup under the
`vs14` role. If migrations fail with a permissions error, the role needs
`CREATE` on the `public` schema:

```sql
GRANT CREATE ON SCHEMA public TO vs14;
```

Do NOT promote `vs14` to superuser to "unblock" migrations.

### First-admin bootstrap

We deliberately ship with no seeded admins. The first operator logs in via
OIDC, which succeeds at the auth layer but fails the admin check in
SS14.Admin. That failed login is enough to register their hub UUID in the
`player` table, from which we seed a god-level admin row by hand.

1. **Log in once** at `https://ss14.zig.computer/admin/` with the target
   Wizden account. Expect an "access denied" style page — that is correct.
2. **Harvest the UUID** from the container logs; the OIDC `sub` claim is
   the hub UUID. The logs never print the client secret, only the
   subject/username of the logger-in:

   ```bash
   docker compose -f ops/ss14-admin/docker-compose.yml logs ss14-admin \
       | grep -E 'sub|ExternalLogin|signin-oidc' | tail -20
   ```

   Cross-reference with `psql`:

   ```sql
   SELECT user_id, last_seen_user_name FROM player
     ORDER BY last_seen_time DESC LIMIT 5;
   ```

3. **Seed the admin row** with the full flag bitmask (value `0x7FFFFFFF`
   grants every permission bit — same mask the upstream docs use for
   "server host" level). Newer SS14.Admin schemas also require a rank
   row; if present, create one first:

   ```sql
   -- Optional, depending on schema version:
   INSERT INTO admin_rank (admin_rank_id, name) VALUES (1, 'Host')
       ON CONFLICT DO NOTHING;

   INSERT INTO admin (user_id, title, admin_rank_id)
       VALUES ('<uuid>', 'Host', 1)
       ON CONFLICT (user_id) DO NOTHING;

   -- Grant every admin flag:
   INSERT INTO admin_flag (admin_id, flag, negative)
       SELECT a.admin_id, f, false
       FROM admin a,
            unnest(ARRAY['HOST','ADMIN','BAN','HELP','LOG','SERVER',
                         'DEBUG','MAPPING','PERMISSIONS','MODERATOR',
                         'QUERY','ROUND','VIEWVAR','ADMINHELP']) AS f
       WHERE a.user_id = '<uuid>'
       ON CONFLICT DO NOTHING;
   ```

   (Exact flag set depends on what enum values the current migration
   defines — `SELECT DISTINCT flag FROM admin_flag;` on the game-server
   DB shows what's in use. The `HOST` flag alone is sufficient for
   everything.)

4. **Re-log** at `/admin/`. The panel should now render.

### Rotating the OIDC client secret

1. Regenerate the secret via the Wizden self-service portal.
2. Update `/etc/vacation-station/admin-oauth.env` on the host:

   ```bash
   sudo $EDITOR /etc/vacation-station/admin-oauth.env
   ```

3. `docker compose -f ops/ss14-admin/docker-compose.yml restart ss14-admin`

No code or git changes are required — the secret is read from the env
file at container start.

### Troubleshooting

| Symptom | Check |
|---|---|
| OIDC redirects to `http://...` | `X-Forwarded-Proto` missing or `ForwardProxies` in appsettings doesn't include the source IP. nginx sets the header; appsettings trusts `127.0.0.1` + `172.16.0.0/12`. |
| `/admin/` returns 404 | nginx `location /admin/` block missing. Re-run `sudo ops/nginx/install.sh`. |
| Container restarts on startup | Almost always a missing env var. `docker compose logs ss14-admin` — if it complains about `Auth:ClientId` or `ConnectionStrings:DefaultConnection` being empty, re-check `/etc/vacation-station/admin-oauth.env` and `/etc/vacation-station/admin-db.env`. |
| Migrations fail with permission error | `GRANT CREATE ON SCHEMA public TO vs14;` — do not make `vs14` a superuser. |
| Login loops back to `/admin/signin-oidc` | User's UUID isn't in the `admin` table. Follow the bootstrap flow above. |
