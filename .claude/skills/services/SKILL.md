---
description: Dev (nix services-flake) vs prod (systemd + docker compose) service runtime handbook
---

# Services

Vacation Station 14 runs two parallel service stacks that share configs but
not runtime managers. This skill is the operator's cheat sheet for which
commands work where. For dev-stack detail see
[`.claude/skills/nix/SKILL.md`](../nix/SKILL.md); for prod runbooks see
[`docs/OPERATIONS.md`](../../../docs/OPERATIONS.md).

## The two stacks

**Dev — `nix run .#dev-services`**

services-flake boots postgres + prometheus + loki + grafana under a
process-compose supervisor. Zero sudo, state in `./.data/` (gitignored),
dev-only literal credentials in `flake.nix`. Reset = `rm -rf .data/`.
Ephemeral by design. Linux-only; macOS uses docker compose instead (see
nix skill "Platform support"). See the nix skill for bring-up, endpoints,
and credentials — do not duplicate here.

**Prod — systemd + docker compose**

Live on the production host. PostgreSQL is apt + systemd; the SS14 watchdog
+ game server run under `ss14-watchdog.service`; backups run on
`ss14-backup.timer`; prometheus/loki/grafana run as a docker compose stack
under `ops/observability/`. Real credentials live in env files and bootstrap
secret files, never committed. Reset is destructive surgery — see
`docs/OPERATIONS.md`.

Flavor A (post-2026-04-12) status: prod runs game server + watchdog +
observability + a growing set of static-site + admin services behind
the nginx edge. See `docs/upstream-sync.md` for the full submodule
list + landed-via beads. Current inventory of fronted services:

- **vs-2y8** — nginx edge on `ss14.zig.computer` (DONE 2026-04-12)
- **vs-1vy** — `/recipes/` ss14-cookbook daily static build
- **vs-1e5** — `/guidebook/` in-game Guidebook daily static render
- **vs-v69** — `/writer/` RMC14-document-simu
- **vs-236** — `/maps/` MapServer + MapViewer
- **vs-35d** — `/admin/` SS14.Admin
- **vs-ygn** — `/nurseshark/` Nurseshark chemistry/medical/cryo app

## Service inventory

Dev + prod coexist on the same host (vs-2f8.7): every dev service binds
at `prod + devPortOffset` (= +1, see `flake.nix`). The Port(s) column
below lists `prod / dev` pairs.

| Service     | Dev manager                             | Prod manager                                    | Port(s) prod / dev           | Repo config                                        |
|-------------|-----------------------------------------|-------------------------------------------------|------------------------------|----------------------------------------------------|
| Postgres    | services-flake `postgres.pg1`, `.data/postgres/` | apt `postgresql-16`, systemd `postgresql.service`, `/var/lib/postgresql/16/main/` | `5432` / `5433`              | `setup.postgres.sh`                                |
| Prometheus  | services-flake `prometheus.prom1`       | docker compose `prom/prometheus`                | `9090` / `9091` (loopback)   | `ops/observability/prometheus.yml`                 |
| Loki        | services-flake `loki.loki1`             | docker compose `grafana/loki`                   | `3100` / `3101` (loopback)   | `ops/observability/loki-config.yml`                |
| Grafana     | services-flake `grafana.graf1`          | docker compose `grafana/grafana`                | `3200` / `3201` (loopback)   | `ops/observability/grafana/`                       |
| Watchdog    | — (don't run in dev)                    | systemd `ss14-watchdog.service`                 | `5000` (loopback, prod only) | `ops/watchdog/ss14-watchdog.service`, `appsettings.yml.example` |
| SS14 server | services-flake `ss14-server` (dotnet run, vs-1ya) | child of watchdog                               | `1212` / `1213` tcp+udp, `44880` / `44881` metrics | `instances/vacation-station/config.toml.example` (dev overlay materialized to `.data/vacation-station/config.toml` on `nix run .#dev-services`) |
| DB backup   | —                                       | systemd `ss14-backup.timer` → `ss14-backup.service` | — (prod only)            | `ops/postgres/backup.sh`, `ss14-backup.{service,timer}` |
| nginx       | —                                       | systemd `nginx.service`                         | `80`, `443` (prod only)      | `ops/nginx/<host>.conf` → `/etc/nginx/sites-available/` (see `.claude/skills/nginx/SKILL.md`) |

Prod game-server port `1212/tcp+udp` is open on the public firewall; dev
`1213/tcp+udp` is also open so launchers can direct-connect to a dev
server running on the same host (`ss14://ss14.zig.computer:1213`). Prod
observability ports are loopback-only (reached via nginx); dev
observability stays loopback, reachable via SSH tunnel if needed.

### Static-site builders (daily rebuild timers)

Nightly oneshot + timer pairs that regenerate static web content
from the live VS14 checkout. All run as `ss14:ss14`, all follow the
same `ops/<name>/build.sh` + `vs14-<name>-build.{service,timer}`
pattern. All served through the same nginx vhost
(`ops/nginx/ss14.zig.computer.conf`).

| Path prefix         | Tool                  | Unit                              | Timer slot    | Serve root                                    | Landed via |
|---------------------|-----------------------|-----------------------------------|---------------|-----------------------------------------------|------------|
| `/recipes/`         | ss14-cookbook         | `vs14-cookbook-build`             | 05:00 UTC     | `/var/www/vs14-recipes/` (rsync)              | vs-1vy     |
| `/guidebook/`       | render.py             | `vs14-guidebook-build`            | 05:15 UTC     | `/var/www/vs14-guidebook/` (rsync)            | vs-1e5     |
| `/nurseshark/`      | Nurseshark (Vite/SPA) | `vs14-nurseshark-build`           | 05:30 UTC     | `/opt/vacation-station/external/nurseshark/dist/` (in-place) | vs-ygn     |
| `/writer/`          | RMC14-document-simu   | `vs14-writer-build`               | ad-hoc        | `/var/www/vs14-writer/` (rsync)               | vs-v69     |
| `/maps/` (tiles)    | SS14.MapServer render | `vs14-map-render`                 | ad-hoc        | MapServer-internal                            | vs-236     |

Nurseshark is the odd one out: it's a BrowserRouter SPA, so nginx needs
`try_files $uri $uri/ /nurseshark/index.html` to route deep-links
client-side (vs-ygn.2), and the Vite build MUST be run with
`VITE_BASE_PATH=/nurseshark/` to bake the prefix into asset URLs
(vs-ygn.1 — `build.sh` grep-gates this). The other static-site
builders produce root-relative HTML that nginx serves directly.

## Deciding which stack to use

Since dev + prod now coexist on the same box (vs-2f8.7), "which stack" is
mostly about which Grafana/ports/creds you point your tooling at — not
about pausing prod. `docker compose ps` and `nix run .#dev-services` can
be running simultaneously.

| Goal                                      | Stack  | Why                                          |
|-------------------------------------------|--------|----------------------------------------------|
| Validate a `prometheus.yml` change        | dev    | ephemeral, fast reset, can't break prod      |
| Test a DB migration                       | dev    | same schema, disposable creds                |
| Iterate on a Grafana dashboard            | dev    | scratchpad, then export JSON into the repo   |
| Playtest a content change against a peer  | dev    | ship them `ss14://ss14.zig.computer:1213` while prod stays on `:1212` |
| Investigate a live bug                    | prod   | dev repro rarely matches real traffic        |
| Test a Discord webhook                    | prod   | scratch channel; real webhook mechanics      |
| Rotate a credential                       | prod   | dev creds are literal                        |

## Common operations

### Start / stop

Dev:
```bash
nix run .#dev-services        # process-compose TUI; F10 to exit
pkill -f process-compose      # or just Ctrl+C
```

Prod:
```bash
# Start everything
sudo systemctl start postgresql ss14-watchdog ss14-backup.timer
cd /opt/vacation-station/ops/observability && docker compose up -d

# Stop everything
cd /opt/vacation-station/ops/observability && docker compose down
sudo systemctl stop ss14-watchdog
# leave postgres running unless you really mean it
```

Restart a single prod service:
```bash
sudo systemctl restart ss14-watchdog
cd /opt/vacation-station/ops/observability && docker compose restart grafana
```

### Status

Dev: the process-compose TUI shows per-service status; or `ss -tln` to
confirm ports are bound.

Prod:
```bash
systemctl status postgresql ss14-watchdog ss14-backup.timer
systemctl list-timers ss14-backup.timer
cd /opt/vacation-station/ops/observability && docker compose ps
pstree -p "$(systemctl show -p MainPID --value ss14-watchdog)"
```

### Logs

Dev: process-compose TUI, or tail `.data/<service>/*.log` directly.

Prod:
```bash
journalctl -u ss14-watchdog -f
journalctl -u ss14-backup.service --since '1 day ago'
journalctl -u postgresql -n 200
cd /opt/vacation-station/ops/observability && docker compose logs -f grafana
```

Application logs also land in Loki once the game server + watchdog are
wired up (see `docs/OPERATIONS.md` "Observability"). Query from Grafana
Explore or `logcli` (both shipped in the nix dev shell).

### Config reload

- **Dev**: Ctrl+C + re-run `nix run .#dev-services`. services-flake
  re-evaluates the flake on each start.
- **Prod systemd**: `sudo systemctl restart <unit>` — re-reads unit file
  and service config. Run `sudo systemctl daemon-reload` first if you
  edited the unit file itself.
- **Prod docker compose**: `docker compose restart <svc>` restarts the
  container but does NOT re-read `docker-compose.yml`. For compose-file
  or env changes, `docker compose up -d <svc>` recreates the container.
  Provisioning files (`grafana/provisioning/`, `prometheus.yml`) are
  bind-mounted, so edit-in-place + restart works.

### Backups

Daily + weekly pg_dump runs unattended via `ss14-backup.timer`. See
`docs/OPERATIONS.md` "Backups" for install, retention, and restore
details. Manual:

```bash
sudo -u postgres /opt/vacation-station/ops/postgres/backup.sh
ls -lh /var/backups/vacation-station/
```

Restore procedure — full steps in `docs/OPERATIONS.md`. Short version:
stop the watchdog, drop + recreate the DB, `pg_restore`, restart.

### Credential rotation

Every prod secret has a documented rotation path in `docs/OPERATIONS.md`.
Summary:

| Credential                       | Where it lives                                              | Rotate via                          |
|----------------------------------|-------------------------------------------------------------|-------------------------------------|
| Postgres `vs14` password         | `/opt/vacation-station/instances/vacation-station/config.toml`, `ops/observability/.env` | `ALTER ROLE vs14 WITH PASSWORD ...` + edit both files + restart watchdog + restart grafana |
| Watchdog `ApiToken`              | `/opt/ss14-watchdog/appsettings.yml`                        | `openssl rand -hex 32` + edit + `systemctl restart ss14-watchdog` |
| Grafana admin password           | `ops/observability/secrets/grafana_admin_password.txt`      | `openssl rand -base64 32 > ...` + `docker compose restart grafana` |
| Discord webhook URL              | `/opt/ss14-watchdog/appsettings.yml`                        | regenerate in Discord + edit + restart watchdog |

Always update the password manager entry after rotating. Dev creds are
literal in `flake.nix` and do not rotate.

### Troubleshooting pointers

- **Prometheus target `gameservers` DOWN** — `docs/OPERATIONS.md`
  "Troubleshooting"
- **No logs in Loki** — same section
- **Grafana datasource errors** — same section
- **Watchdog won't start / `KillMode` / `OOMPolicy` semantics** —
  `docs/OPERATIONS.md` "Watchdog / Systemd unit semantics"
- **Backup timer silent** — `journalctl -u ss14-backup.service --since
  '1 day ago'`, `systemctl list-timers ss14-backup.timer`
- **Dev stack won't bind a port** — prod docker stack collides only if
  something is already on the +1 port (5433/9091/3101/3201). Usually
  that's a stray `process-compose` from a previous `nix run
  .#dev-services` that didn't clean up. `ss -tlnp | grep <port>` to
  identify; `pkill -INT -f 'process-compose --no-server'` to clear.

### Config file discipline

Repo-committed templates end in `.example`. Populated runtime files live
outside the repo (`/opt/ss14-watchdog/...`, `/etc/vacation-station/...`,
`ops/observability/.env`, `ops/observability/secrets/...`) and are
gitignored. Editing a `.example` file does NOT change a running service;
the populated copy is what's read at runtime. Re-running the `setup.*.sh`
scripts is idempotent and will NOT clobber an existing populated config.

## Deploying changes

Prod is a second clone of this repo at `/opt/vacation-station/`, kept
in sync via `git pull`. The canonical deploy flow is one-way:

```
1. Edit configs in the DEV clone: /home/ubuntu/vacation-station-14/
2. Commit + push to origin
3. On the PROD clone:
     cd /opt/vacation-station && git pull --rebase
     (add `git submodule update --init --recursive` if submodules changed)
4. Apply to the live system (pick one per service type):
     docker compose:  cd /opt/vacation-station/ops/<name> && sudo docker compose up -d
     systemd unit:    sudo systemctl restart <unit>.service
5. Verify: docker ps / systemctl status / targeted HTTP probe
```

**NEVER direct-edit files under `/opt/vacation-station/`.** The clone
there is a read-only mirror maintained by `git pull`. If you find
yourself wanting to touch `/opt/` directly, you almost certainly want
to edit `/home/`, commit, push, and pull instead.

### Subagents doing ops work

Subagents dispatched for ops tasks must edit only:
- their own **worktree** (for the commit that lands in the repo), and
- the **live deploy location** under `/opt/` (for the running service
  to pick up the change immediately).

Do **NOT** sync edits to the main `/home/ubuntu/vacation-station-14/`
clone directly — the orchestrator's merge handles that after the
worktree is merged. Direct main-clone edits cause merge conflicts
because the uncommitted changes collide with what the merge brings in
(observed during vs-2f8.4; see its post-mortem in the bead history).

When dispatching an ops subagent that needs to edit tracked files,
include `mode: "acceptEdits"` on the `Agent` call — background
subagents can't surface permission prompts interactively, and the
default mode auto-denies Edit/Write on tracked files (observed
blocker on vs-2f8.5's first dispatch attempt; see vs-2f8.6 for the
investigation).

## Don't

- Don't hardcode dev port numbers. `flake.nix` uses `devPortOffset = 1`
  as the single source of truth; every dev service is `prod + 1`. If you
  change that constant, everything shifts — don't spray `5433` /
  `9091` / etc. into configs or docs.
- Don't bind dev Prometheus / Loki / Grafana to a public interface. The
  dev SS14 game port `1213/tcp+udp` is intentionally open at the host
  firewall so peers can `ss14://ss14.zig.computer:1213` into a local
  playtest; dev observability stays loopback (reach it via SSH tunnel or
  local browser only).
- Don't commit anything from `.data/`, `ops/observability/.env`, or
  `ops/observability/secrets/*` (other than `.gitkeep` / `.example`).
- Don't edit `.data/vacation-station/config.toml` and expect edits to
  persist between `nix run .#dev-services` runs — the flake materializes
  it from the committed `.example` on every boot. If you want a change
  to stick, edit `instances/vacation-station/config.toml.example`.
- Don't edit other `.example` files expecting a running service to pick
  up changes. Edit the populated copy.
- Don't bind prod Prometheus / Loki / Grafana / watchdog admin API to a
  public interface. The watchdog admin API is fronted by nginx at
  `https://ss14.zig.computer/watchdog/` (vs-2y8); Prometheus / Loki /
  Grafana stay loopback-only and operators SSH-tunnel to reach
  Grafana. See `docs/OPERATIONS.md` "Operator access" + `docs/NETWORKING.md`
  for the (currently unused) public-Grafana vhost template.
- Don't use dev-stack credentials (`vs14 / dev-only-insecure`, `admin /
  admin`) anywhere near prod.
