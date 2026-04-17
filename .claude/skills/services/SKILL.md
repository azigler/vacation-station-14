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

Flavor A (post-2026-04-12) status: prod is pure-SS14 game server + watchdog
+ observability; no external services yet. Coming:

- **vs-2y8** — nginx in front of the watchdog admin API (DONE 2026-04-12;
  system-wide nginx edge live on `ss14.zig.computer`)
- **vs-1vy** — cookbook service
- **vs-236** — mapserver
- **vs-35d** — SS14.Admin

Those will extend the prod topology when they land; this skill covers
current state.

## Service inventory

| Service     | Dev manager                             | Prod manager                                    | Port(s)             | Repo config                                        |
|-------------|-----------------------------------------|-------------------------------------------------|---------------------|----------------------------------------------------|
| Postgres    | services-flake `postgres.pg1`, `.data/postgres/` | apt `postgresql-16`, systemd `postgresql.service`, `/var/lib/postgresql/16/main/` | `5432`              | `setup.postgres.sh`                                |
| Prometheus  | services-flake `prometheus.prom1`       | docker compose `prom/prometheus`                | `9090` (loopback)   | `ops/observability/prometheus.yml`                 |
| Loki        | services-flake `loki.loki1`             | docker compose `grafana/loki`                   | `3100` (loopback)   | `ops/observability/loki-config.yml`                |
| Grafana     | services-flake `grafana.graf1`          | docker compose `grafana/grafana`                | `3200` (loopback)   | `ops/observability/grafana/`                       |
| Watchdog    | — (don't run in dev)                    | systemd `ss14-watchdog.service`                 | `5000` (loopback)   | `ops/watchdog/ss14-watchdog.service`, `appsettings.yml.example` |
| SS14 server | `dotnet run --project Content.Server`   | child of watchdog                               | `1212/tcp+udp`, `44880` metrics (loopback) | `instances/vacation-station/config.toml.example` |
| DB backup   | —                                       | systemd `ss14-backup.timer` → `ss14-backup.service` | —               | `ops/postgres/backup.sh`, `ss14-backup.{service,timer}` |
| nginx       | —                                       | systemd `nginx.service`                         | `80`, `443`         | `ops/nginx/<host>.conf` → `/etc/nginx/sites-available/` (see `.claude/skills/nginx/SKILL.md`) |

Dev + prod Grafana both bind `:3200`, so they cannot co-exist on the same
host. This is a feature — pick one.

## Deciding which stack to use

| Goal                                      | Stack  | Why                                          |
|-------------------------------------------|--------|----------------------------------------------|
| Validate a `prometheus.yml` change        | dev    | ephemeral, fast reset, can't break prod      |
| Test a DB migration                       | dev    | same schema, disposable creds                |
| Iterate on a Grafana dashboard            | dev    | scratchpad, then export JSON into the repo   |
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
- **Dev stack won't bind a port** — prod docker stack or a stray
  process-compose is still up. `ss -tlnp | grep <port>` to identify.

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

- Don't run `nix run .#dev-services` and the docker compose stack on the
  same host at the same time — they collide on 5432 / 9090 / 3100 / 3200.
- Don't commit anything from `.data/`, `ops/observability/.env`, or
  `ops/observability/secrets/*` (other than `.gitkeep` / `.example`).
- Don't edit `.example` files expecting a running service to pick up
  changes. Edit the populated copy.
- Don't bind prod Prometheus / Loki / Grafana / watchdog admin API to a
  public interface. Grafana goes out through nginx (vs-2y8, live on
  `ss14.zig.computer`); everything else stays loopback.
- Don't use dev-stack credentials (`vs14 / dev-only-insecure`, `admin /
  admin`) anywhere near prod.
