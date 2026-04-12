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
