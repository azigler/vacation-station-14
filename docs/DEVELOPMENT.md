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

### Platform notes

The flake supports `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, and
`aarch64-darwin` natively. `shell.nix` branches deps on `stdenv` — Linux
pulls the full client runtime (X11/Wayland/mesa/ALSA/gtk), darwin gets a
server-only shell with just the build toolchain + ops-validation tools.

- **Linux** — clone + `direnv allow`. Full client + server. `nix run
  .#dev-services` works.
- **macOS** — clone + `direnv allow`. Server-only dev shell (dotnet build,
  Content.Server, tests, ops tools). Running the client (Content.Client)
  requires a Linux VM — Content.Client's X11/GL/audio stack is not packaged
  for darwin, and wiring Metal/CoreAudio is out of scope here.
  `nix run .#dev-services` is Linux-only; macOS contributors use
  `ops/observability/docker-compose.yml` for dev observability.
- **Windows** — no native nix on Windows. Use WSL2 (subsection below).

See `.claude/skills/nix/SKILL.md` for the full platform-support matrix.

### Windows (via WSL2)

Windows contributors run the entire nix dev path inside a WSL2 Ubuntu
distro. Steps:

1. **Install WSL2 + Ubuntu** (admin PowerShell):
   ```powershell
   wsl --install -d Ubuntu-24.04
   ```
   Reboot if prompted, then launch "Ubuntu" from the Start menu and finish
   the first-run user setup.

2. **Install nix** inside the WSL shell. We recommend the
   [Determinate Systems installer](https://determinate.systems/posts/determinate-nix-installer/)
   because it enables flakes by default and includes a clean uninstaller:
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L \
     https://install.determinate.systems/nix | sh -s -- install
   ```
   (Official multi-user installer from <https://nixos.org/download.html>
   also works, but you'll need to enable flakes in `~/.config/nix/nix.conf`.)

3. **Install direnv**:
   ```bash
   sudo apt install direnv
   echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
   exec bash
   ```

4. **Clone the repo inside the WSL filesystem**, NOT on `/mnt/c/...`:
   ```bash
   cd ~
   git clone https://github.com/azigler/vacation-station-14.git
   cd vacation-station-14
   direnv allow
   ```
   Crossing the Windows/Linux filesystem boundary (`/mnt/c`) kills build
   performance and breaks inotify — always keep the repo under
   `~/` (e.g. `~/vacation-station-14`).

5. **Build and run**:
   ```bash
   dotnet run --project Content.Server     # server — reliable under WSL2
   nix run .#dev-services                  # dev postgres/prom/loki/grafana
   ```

**Client (Content.Client):** WSLg (Windows 11+) forwards X11/Wayland and
PulseAudio to the host, so `dotnet run --project Content.Client` often
launches a window — but OpenGL and audio through WSLg are experimental and
you should expect rendering glitches, vsync problems, or audio dropouts.
For a reliable Windows client experience, use the
[SS14 launcher](https://spacestation14.io/about/nightly/) on the Windows
side and connect it to a server running inside WSL2 (direct-connect to
`localhost`, since WSL2 forwards localhost ports to the host).

**Do not recommend:**
- Running nix natively on Windows (it doesn't exist).
- Cloning to `/mnt/c/...` and accessing from WSL — the performance hit is
  severe and tooling misbehaves.

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

`shell.nix` pins: `dotnet-sdk_10`, Python 3, pre-commit, and ops validation
tools (`shellcheck`, `yamllint`, `prometheus` → provides `promtool`,
`grafana-loki` → provides `loki` + `logcli`, `grafana` → provides
`grafana-cli`). On Linux the shell additionally pins the full client
runtime (glfw, openal, freetype, fluidsynth, gtk3, X11/Wayland, mesa,
ALSA, dbus). On darwin those client-runtime deps are omitted — the shell
is server-only there. Everything pinned in `flake.lock` — identical across
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

Dev services bind at **prod + 1** (single source of truth is
`devPortOffset = 1` in `flake.nix`). This lets the dev stack coexist with
a live prod stack on the same host — see [Running dev on the same box as
prod](#running-dev-on-the-same-box-as-prod) below.

| Service     | URL / port              | Notes |
|-------------|-------------------------|-------|
| Postgres    | `localhost:5433`        | db `vacation_station`, user `vs14` |
| Prometheus  | `http://localhost:9091` | scrapes `localhost:44881` (dev SS14 server) |
| Loki        | `http://localhost:3101` | push + query API |
| Grafana     | `http://localhost:3201` | provisioned datasources + dashboards |

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

Every time `nix run .#dev-services` boots, it writes a dev config.toml to
`./.data/vacation-station/config.toml` — already on the +1 ports, with
dev-literal credentials filled in. Point the SS14 server at it:

```bash
dotnet run --project Content.Server -- \
  --config-file .data/vacation-station/config.toml \
  --data-dir    .data/vacation-station
```

The generated config has the relevant sections already offset to +1:

```toml
[database]
engine = "postgres"
pg_host = "localhost"
pg_port = 5433                     # +1 from prod 5432
pg_database = "vacation_station"
pg_username = "vs14"
pg_password = "dev-only-insecure"

[status]
bind = "*:1213"                    # +1 from prod 1212

[metrics]
enabled = true
host = "*"
port = 44881                       # +1 from prod 44880

[loki]
enabled = true
name = "vacation-station"          # must match the Prometheus `server` label
address = "http://localhost:3101"  # +1 from prod 3100
```

Dev Prometheus will start scraping `localhost:44881` once the SS14
server is up and the `[metrics]` endpoint is live. Loki ingest is
push-based — Robust sends log lines directly.

If you edit `.data/vacation-station/config.toml` between stack starts,
those manual edits are discarded — the nix overlay rewrites the file on
every boot of `nix run .#dev-services`. The source of truth is
`flake.nix` (which reads from the committed `config.toml.example` and
applies the offset rewrites); add anything you want persistent to the
committed template.

> **Auto-launch deferred.** process-compose currently does NOT launch
> the SS14 dev game server itself; you run `dotnet run --project
> Content.Server ...` manually in a second terminal after the
> observability stack is up. Wiring the server under process-compose is
> tracked in vs-1ya.

### Running dev on the same box as prod

The dev stack's ports (5433 / 9091 / 3101 / 3201 / 1213 / 44881) are all
prod-port + 1, so you can run the full `nix run .#dev-services`
observability stack AND a `dotnet run` dev game server alongside a live
prod stack without port collisions. Concrete example (what ships on
`ss14.zig.computer` today):

| Thing                 | Prod (docker / systemd)         | Dev (services-flake)               |
|-----------------------|---------------------------------|------------------------------------|
| Postgres              | apt + systemd, `:5432`          | services-flake, `:5433` in `.data/postgres/` |
| Prometheus            | docker `:9090`                  | services-flake, `:9091`            |
| Loki                  | docker `:3100`                  | services-flake, `:3101`            |
| Grafana               | docker `:3200`                  | services-flake, `:3201`            |
| SS14 game server      | watchdog + systemd, `:1212`     | `dotnet run`, `:1213`              |
| SS14 metrics endpoint | `:44880`                        | `:44881`                           |

The dev SS14 server is reachable from any SS14 launcher by direct-connect
at `ss14://ss14.zig.computer:1213` (firewall already opens this port).
Prod keeps advertising on the public hub at `:1212`; dev is private
direct-connect only (its `[hub] advertise = false`).

Workflow when iterating on the same box as prod:

1. `nix run .#dev-services` — starts postgres/prom/loki/grafana on +1
   ports and materializes `.data/vacation-station/config.toml`.
2. In another shell (same dev shell): `dotnet run --project Content.Server
   -- --config-file .data/vacation-station/config.toml --data-dir
   .data/vacation-station`.
3. In a launcher on any machine: Direct Connect →
   `ss14://ss14.zig.computer:1213`.
4. Browse dev Grafana at `http://localhost:3201` (or through an SSH
   tunnel if you're offbox; don't publish dev Grafana publicly — prod
   Grafana is the only Grafana behind nginx/OIDC).
5. `F10` / Ctrl+C in process-compose to tear down dev services. `Ctrl+C`
   in the `dotnet run` terminal to stop the dev game server. Prod is
   untouched.

If you want to reset dev state entirely without touching prod:
```bash
rm -rf .data/
```

`flake.nix` defines `devPortOffset = 1` as the single source of truth —
if you ever need a different offset (e.g. running TWO dev stacks for A/B
testing), bump the constant and every service + the generated game-server
config shifts in lockstep.

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
  overlay only rewrites `host.docker.internal` → `localhost` and the
  scrape port from prod `44880` → dev `44881` in-memory. Scrape interval,
  job name, labels, `server: vacation-station` contract all identical.
- Loki config (`ops/observability/loki-config.yml`) — only the `/loki`
  path prefix and the http/grpc listen ports are rewritten (to the dev
  dataDir and `3101`/`9097`). Retention, schema, compactor settings
  unchanged.
- Grafana datasources — Prometheus + Loki match prod (just with localhost
  URLs). See the note below on Postgres.
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
- No TLS / nginx reverse proxy in front of grafana
- Data in project `./.data/` instead of `/var/lib/*`
- **No Postgres Grafana datasource.** Prod uses the
  `grafana-postgresql-datasource` plugin (installed at container boot via
  `GF_INSTALL_PLUGINS`). services-flake's grafana module has no runtime
  plugin-install hook and the plugin isn't in nixpkgs `grafanaPlugins`, so
  the dev stack omits the datasource entirely. Postgres-backed panels on
  the Game Servers / Perf Metrics dashboards will render "no datasource"
  locally. Prometheus + Loki panels are unaffected. If you need to
  exercise Postgres panels against live data, spin up the full
  `ops/observability/docker-compose.yml` stack (pointed at a local
  `postgres` if desired) instead of the dev flake. Tracked under vs-3oe.

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

VS14 tracks multiple upstreams, each with its own integration mode
(engine submodule, scoped base-content refresh, sibling-fork cherry-
pick, deploy-as-is submodule). The authoritative per-upstream table
lives in [`upstream-sync.md`](upstream-sync.md); the per-mode
workflow lives in [`.claude/skills/upstream-sync/SKILL.md`](../.claude/skills/upstream-sync/SKILL.md).

Conflict resolution bias:
- `_VS/` — keep ours
- `_<FORK>/` (e.g. `_DV/`, `_NF/`) — respect upstream intent; annotate
  resolution edits with `// <FORK> - …`
- Unprefixed `Content.*` (SS14 base) — re-apply `// VS` annotations
  on top of upstream changes
- `.github/` workflows — keep ours unless deliberately pulling
  upstream's
- `RobustToolbox/` submodule — bumped only in dedicated engine-bump
  commits; never modified by cherry-picks

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

- **[Rider](https://www.jetbrains.com/rider/)** — Recommended IDE (free for non-commercial)
- **[Robust YAML VS Code extension](https://marketplace.visualstudio.com/items?itemName=ss14.ss14-yaml)** — YAML validation for prototypes

## SS14 Reference

- [Upstream SS14 developer docs](https://docs.spacestation14.com/)
- [Space Station 14](https://github.com/space-wizards/space-station-14) (base; `upstream-sw`)
- [RobustToolbox](https://github.com/space-wizards/RobustToolbox) (engine; submodule pin)
- [Delta-V Station](https://github.com/DeltaV-Station/Delta-v) (sibling fork; `upstream-dv`, cherry-pick source)
- [`upstream-sync.md`](upstream-sync.md) — authoritative list of tracked upstreams
