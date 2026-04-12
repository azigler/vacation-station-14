# Developing Vacation Station 14

**Nix is the primary dev path.** It pins the entire build + ops toolchain
(`dotnet-sdk_10`, `shellcheck`, `yamllint`, `promtool`, `loki`, `grafana-cli`,
…), and `services-flake` boots a local postgres/prometheus/loki/grafana stack
without docker or sudo. See [`/nix` skill](../.claude/skills/nix/SKILL.md)
for the concise reference.

## Quick Start (Nix)

```bash
git clone https://github.com/azigler/vacation-station-14.git
cd vacation-station-14
direnv allow                           # one-time per clone
# cd-triggered env load now handles the rest

dotnet run --project Content.Server    # headless
dotnet run --project Content.Client    # needs GPU/audio
```

Without direnv:
```bash
nix develop
```

Connect via launcher → Direct Connect → `localhost`.

**Flake is Linux-only** (`x86_64-linux` + `aarch64-linux`) — `shell.nix`
pulls libdrm/mesa/xorg which don't build on darwin. macOS contributors: use
a Linux VM or the system-install path below.

## Quick Start (system-install, non-Nix)

Same path a production host uses. Only choose this if you don't want nix.

```bash
git clone https://github.com/azigler/vacation-station-14.git
cd vacation-station-14
./setup.ubuntu.sh
dotnet run --project Content.Server
```

Prerequisites:
- .NET 10 SDK
- Python 3.7+ (for `RUN_THIS.py`)
- Git
- Ubuntu 22.04 / 24.04 or equivalent

See [setup.ubuntu.sh](../setup.ubuntu.sh) for the automated install.

## What's in the Nix dev shell

`shell.nix` pins: `dotnet-sdk_10`, Python 3, pre-commit, full client stack
(glfw, openal, freetype, fluidsynth, X11/Wayland, audio), and ops validation
tools (`shellcheck`, `yamllint`, `prometheus` → provides `promtool`,
`grafana-loki` → provides `loki` + `logcli`, `grafana` → provides
`grafana-cli`). Everything pinned in `flake.lock` — identical across
contributors and CI.

## Dev Services Stack

For local validation of observability configs and DB migrations without
touching the production (apt + systemd + docker-compose) path, the flake
ships a `process-compose`-based stack via
[services-flake](https://community.flake.parts/services-flake).

```bash
nix run .#dev-services
```

That boots four services as user processes (no sudo, no docker) bound to
`localhost`, with state under `.data/` (gitignored). The TUI is
process-compose; `F10` exits, arrow keys select a process to inspect its
logs.

### Endpoints

| Service     | URL / port             | Notes |
|-------------|------------------------|-------|
| Postgres    | `localhost:5432`       | db `vacation_station`, user `vs14` |
| Prometheus  | `http://localhost:9090` | scrapes `localhost:44880` (SS14 server) |
| Loki        | `http://localhost:3100` | push + query API |
| Grafana     | `http://localhost:3000` | provisioned datasources + dashboards |

### Dev-only credentials (do NOT reuse in prod)

These are literals embedded in `flake.nix` for dev convenience. The
production path (vs-3ty postgres, vs-2p3 observability) uses a 32-byte
random postgres password loaded from `/etc/vacation-station/postgres.env`
and a separate grafana admin password via docker secrets — none of which
are ever committed.

| Credential               | Value                |
|--------------------------|----------------------|
| Postgres user / password | `vs14 / dev-only-insecure` |
| Grafana admin / password | `admin / admin`      |

### Wiring a dev SS14 server

Point `server_config.toml` (or equivalent cvars):

```toml
[database]
engine = "postgres"
pg_host = "localhost"
pg_port = 5432
pg_database = "vacation_station"
pg_username = "vs14"
pg_password = "dev-only-insecure"

[metrics]
enabled = true
host = "localhost"
port = 44880

[loki]
enabled = true
name = "vacation-station"   # must match the Prometheus `server` label
address = "http://localhost:3100"
```

Prometheus will start scraping `localhost:44880` once the SS14 server is
up and the `[metrics]` endpoint is live. Loki ingest is push-based —
Robust sends log lines directly.

### Reset state

```bash
rm -rf .data/
```

Wipes postgres, prometheus, loki, and grafana storage. Run again with
`nix run .#dev-services` and the stack reinitializes from scratch
(postgres reruns `initialScript`, grafana re-provisions from the
committed YAML, etc.).

### Parity with production

**Same:**
- Prometheus scrape config (`ops/observability/prometheus.yml`) — the dev
  overlay only rewrites `host.docker.internal` → `localhost` in-memory.
  Scrape interval, job name, labels, `server: vacation-station` contract
  all identical.
- Loki config (`ops/observability/loki-config.yml`) — only `/loki` path
  prefixes rewrite to `./.data/loki`. Retention, schema, compactor
  settings unchanged.
- Grafana datasources — same shape as `ops/observability/grafana/
  provisioning/datasources/datasources.yml`, just with localhost URLs
  and the dev password literal instead of `$POSTGRES_PASSWORD`.
- Grafana dashboards — sourced directly from
  `ops/observability/grafana/dashboards/` (same JSON files prod loads).
- Postgres schema — SS14's EF Core migrations run identically; the
  `vacation_station` database with owner `vs14` is the exact shape
  vs-3ty provisions on the Ubuntu host.

**Different (dev only):**
- No systemd (process-compose supervises instead)
- No auto-start across reboots (relaunch manually)
- No backup / WAL archival
- Insecure literal credentials
- No TLS / Caddy reverse proxy in front of grafana
- Data in project `./.data/` instead of `/var/lib/*`

### Relationship to prod beads

- [vs-3ty](../.beads/issues.jsonl) — production postgres bring-up
  (apt install, systemd unit, `/etc/vacation-station/postgres.env`)
- [vs-h3u](../.beads/issues.jsonl) — SS14.Watchdog systemd supervision
- [vs-2p3](../.beads/issues.jsonl) — observability docker-compose stack
  (prometheus + loki + grafana + promtail) with docker secrets

This dev stack is a zero-sudo companion to those — it does not replace
them and is not appropriate for a production host.

## Repository Layout

```
.
├── Content.Server/          Server game logic
│   └── _VS/                  Our custom server code
├── Content.Client/          Client UI and rendering
│   └── _VS/                  Our custom client code
├── Content.Shared/          Shared game logic
│   └── _VS/                  Our custom shared code
├── Content.Tests/           Unit tests
├── Content.IntegrationTests/ Integration tests
├── Content.YAMLLinter/      YAML prototype validator
├── Resources/
│   ├── Prototypes/_VS/       Our entity prototypes (YAML)
│   ├── Locale/en-US/_VS/     Our localization
│   ├── Textures/_VS/         Our sprites
│   └── Audio/_VS/            Our sounds
├── RobustToolbox/           Engine submodule (don't modify)
├── .claude/                 AI-assisted development harness
│   ├── skills/              Pipeline skills (orient, spec, impl, etc.)
│   └── settings.json        Hook configuration
├── hooks/                   Hook scripts (session, lint, commit checks)
├── docs/                    Documentation
├── CLAUDE.md                Project conventions
├── CONTRIBUTING.md          Contribution guidelines
└── LEGAL.md                 Licensing details
```

## Common Commands

### Build
```bash
dotnet build                                  # debug build
dotnet build --configuration DebugOpt         # CI-equivalent optimized debug
dotnet build --configuration Release          # production build
```

### Test
```bash
dotnet test Content.Tests --no-build                  # unit tests
dotnet test Content.IntegrationTests --no-build       # integration tests
dotnet run --project Content.YAMLLinter               # validate YAML prototypes
```

### Full quality gate (run before commits / merges)
```bash
dotnet build --configuration DebugOpt \
  && dotnet test Content.Tests --no-build --configuration DebugOpt \
  && dotnet test Content.IntegrationTests --no-build --configuration DebugOpt \
  && dotnet run --project Content.YAMLLinter \
  && dotnet format --verify-no-changes
```

### Format code
```bash
dotnet format                # format everything
dotnet format --include Content.Server/_VS/**/*.cs    # format specific files
```

### Package for distribution
```bash
dotnet build Content.Packaging -c Release
dotnet run --project Content.Packaging server --hybrid-acz --platform linux-x64
# Output in ./release/
```

## Upstream Sync

We track Delta-V upstream. Periodic merges:

```bash
git fetch upstream
git log --oneline upstream/master -10    # review incoming
git merge upstream/master
# resolve conflicts: always keep _VS code, merge upstream carefully
dotnet build && dotnet test Content.Tests --no-build
git push
```

Conflict resolution rules:
- `_VS/` files — keep ours
- `_DV/` files — take theirs (upstream Delta-V)
- Upstream files we modified — merge carefully, preserve our `// VS` annotations
- `.github/` workflows — take theirs unless we have VS overrides
- `RobustToolbox` submodule — take theirs

## Writing New Content

See `.claude/skills/prototype/SKILL.md` for YAML conventions and `.claude/skills/spec/SKILL.md` for the formal spec workflow.

Quick pattern: new C# code goes in `Content.Server/_VS/FeatureName/`, new prototypes in `Resources/Prototypes/_VS/Category/`, localization in `Resources/Locale/en-US/_VS/category.ftl`.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `RobustToolbox/` is empty | `git submodule update --init --recursive` or `python RUN_THIS.py` |
| CI fails with "RobustToolbox submodule modified" | `git checkout upstream/master RobustToolbox` |
| CRLF line ending error | `dos2unix <file>` or configure editor for LF |
| `System.DllNotFoundException: SharpFont.FT` | `sudo apt install libfreetype6` |
| libssl version mismatch | `export CLR_OPENSSL_VERSION_OVERRIDE=48` |
| Slow first build | Normal — NuGet is restoring packages (~5 min) |
| ARM64 doesn't work | Robust Toolbox < 267.0.0 lacks ARM64; use x64 emulation |

## Additional Tools

- **[RSIEdit](https://github.com/space-wizards/RSIEdit)** — GUI for editing sprite (.rsi) files. Needed if you're drawing or porting sprites.
- **[Rider](https://www.jetbrains.com/rider/)** — Recommended IDE (free for non-commercial)
- **[Robust YAML VS Code extension](https://marketplace.visualstudio.com/items?itemName=ss14.ss14-yaml)** — YAML validation for prototypes

## SS14 Reference

- [Upstream SS14 developer docs](https://docs.spacestation14.com/)
- [Delta-V Station](https://github.com/DeltaV-Station/Delta-v) (our direct upstream)
- [Space Station 14](https://github.com/space-wizards/space-station-14) (original project)
- [RobustToolbox](https://github.com/space-wizards/RobustToolbox) (engine)
