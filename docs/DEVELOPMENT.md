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

| Service     | URL / port             | Notes |
|-------------|------------------------|-------|
| Postgres    | `localhost:5432`       | db `vacation_station`, user `vs14` |
| Prometheus  | `http://localhost:9090` | scrapes `localhost:44880` (SS14 server) |
| Loki        | `http://localhost:3100` | push + query API |
| Grafana     | `http://localhost:3200` | provisioned datasources + dashboards |

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
- No TLS / Caddy reverse proxy in front of grafana
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
