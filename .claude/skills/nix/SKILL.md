---
description: Nix dev environment + services-flake dev stack (postgres/prom/loki/grafana)
---

# Nix

Nix is the **primary** dev path for Vacation Station 14. The flake pins the
entire build + ops toolchain, and `services-flake` boots a local
postgres/prometheus/loki/grafana stack without docker or sudo.

System-install (apt + `./setup.ubuntu.sh`) remains supported and is the only
path for production hosts. For dev: prefer nix.

## Enter the dev shell

```bash
direnv allow           # one-time per worktree (worktree subagents: handled by session-start hook)
# now cd'ing into the repo auto-loads the flake env
```

Or without direnv:
```bash
nix develop
```

The shell puts `dotnet`, graphics libs, `shellcheck`, `yamllint`, `promtool`,
`loki`, `grafana-cli`, and the Delta-V pre-commit toolchain on PATH. Pinned
to `flake.lock` — everyone gets the same versions.

## Belt-and-suspenders in non-interactive shells

If you're scripting and can't rely on direnv having fired:

```bash
eval "$(direnv export bash)" 2>/dev/null; dotnet build
eval "$(direnv export bash)" 2>/dev/null; promtool check config ops/observability/prometheus.yml
```

Safe no-op if the env is already active, cheap on repeat thanks to the local
nix store cache.

## Dev services stack

Zero-sudo postgres + prometheus + loki + grafana, reading the SAME configs
we ship in `ops/observability/` (with small in-memory dev overlays).

```bash
nix run .#dev-services    # process-compose TUI; F10 to exit
```

| Service    | Endpoint                | Dev creds                       |
|------------|-------------------------|---------------------------------|
| Postgres   | `localhost:5433`        | `vs14 / dev-only-insecure`      |
| Prometheus | `http://localhost:9091` | —                               |
| Loki       | `http://localhost:3101` | —                               |
| Grafana    | `http://localhost:3201` | `admin / admin`                 |

Dev ports are `prod + 1` via `devPortOffset = 1` in `flake.nix` — the dev
stack is designed to coexist with a live prod stack on the same host
(vs-2f8.7). See `docs/DEVELOPMENT.md` "Running dev on the same box as
prod" for the full two-stacks workflow.

State lives in `.data/` (gitignored); `.data/vacation-station/config.toml`
is regenerated from the committed `instances/vacation-station/config.toml.example`
on every stack boot (dev ports + dev-literal credentials). Reset with
`rm -rf .data/`.

Dev credentials are literal strings and MUST NOT be reused in prod. The
production stack (vs-3ty postgres, vs-2p3 observability) uses random
passwords loaded from env files / docker secrets.

## When to use which path

| Task                                          | Use                                    |
|-----------------------------------------------|----------------------------------------|
| Local build / run / test (Linux)              | nix dev shell                          |
| Local build / run / test (macOS)              | nix dev shell (server-only) + Linux VM for client |
| Local build / run / test (Windows)            | WSL2 + nix dev shell (see `docs/DEVELOPMENT.md`) |
| Contributor onboarding                        | nix + direnv                           |
| CI on GH Actions                              | nix (reproducible)                     |
| Validate `prometheus.yml` / `loki-config.yml` | `promtool` / `loki -verify-config` in the dev shell |
| Spin up postgres for migration testing        | `nix run .#dev-services` (Linux; macOS uses docker-compose) |
| Iterate on a Grafana dashboard                | `nix run .#dev-services`, edit JSON, restart stack |
| Production host bring-up                      | `./setup.ubuntu.sh` + `setup.postgres.sh` + watchdog + docker-compose (see `docs/OPERATIONS.md`) |

## Platform support

| Platform         | Native nix   | Dev shell                              | `nix run .#dev-services` | Notes |
|------------------|--------------|----------------------------------------|--------------------------|-------|
| x86_64-linux     | yes          | yes (client + server)                  | yes                      | Full stack.                                                       |
| aarch64-linux    | yes          | yes (client + server)                  | yes                      | Full stack.                                                       |
| x86_64-darwin    | yes          | yes (server-only)                      | no                       | Client needs a Linux VM; use docker-compose for dev observability. |
| aarch64-darwin   | yes          | yes (server-only)                      | no                       | Client needs a Linux VM; use docker-compose for dev observability. |
| Windows (WSL2)   | via WSL      | yes (server-only reliable; WSLg client experimental) | yes (inside WSL) | See `docs/DEVELOPMENT.md` "Windows (via WSL2)".                    |

`shell.nix` branches on `stdenv` platform: Linux pulls the full client
runtime (X11/Wayland/mesa/ALSA/gtk), darwin gets only the build toolchain
and ops-validation tools. The `packages.dev-services` output (services-flake
postgres + prom + loki + grafana) is gated to Linux via `lib.mkIf
pkgs.stdenv.isLinux` — services-flake's supervision and some of the bundled
service configs don't reliably evaluate on darwin. macOS contributors run
the production docker-compose observability stack instead.

## Worktree subagents

The `session-start.sh` hook auto-runs `direnv allow .` in any worktree with
an `.envrc`, so per-path approval is always in place before the agent's
first tool call. If a subagent command needs the flake toolchain and isn't
getting it (e.g. `which shellcheck` resolves to `/usr/bin/shellcheck`
instead of a `/nix/store/...` path), force-activate with the direnv export
one-liner shown above.

## Package name gotchas

When adding tools to `shell.nix`:

- `loki` as a top-level attr **does not exist** in nixpkgs 25.11 — use
  `grafana-loki` (provides `loki` + `logcli`).
- `grafana-cli` ships inside `grafana`, not a separate package.
- `promtool` ships inside `prometheus`.
- `grafana-postgresql-datasource` is the canonical Grafana Postgres
  datasource (SS14 upstream dashboards and our provisioning both use it).
  It is NOT in nixpkgs `grafanaPlugins`, and services-flake's grafana
  module has no runtime plugin-install hook. Prod grafana installs it at
  container boot via `GF_INSTALL_PLUGINS`; the dev services-flake stack
  omits the Postgres datasource entirely. Postgres-backed dashboard panels
  render "no datasource" locally; Prometheus + Loki panels are unaffected.
  See vs-3oe and `docs/DEVELOPMENT.md` "Parity with production".

## Working on the flake itself

```bash
nix flake show                    # list outputs
nix flake check --no-build        # evaluate without building
nix flake update                  # bump all inputs (review flake.lock diff carefully)
nix flake lock --update-input nixpkgs   # bump one input
```

Flake-parts owns the outputs structure — `perSystem = { ... }:` is where
`devShells.default` and `packages.dev-services` live. services-flake is
imported as a process-compose module.

## Don't

- Don't assume dev and prod are mutually exclusive — post-vs-2f8.7 they
  coexist on `prod-port + 1` (5433/9091/3101/3201/1213/44881 for dev vs
  5432/9090/3100/3200/1212/44880 for prod). If you're hardcoding a dev
  port anywhere, use `devPortOffset = 1` from `flake.nix` instead.
- Don't bind dev services to a public interface. Everything except the
  SS14 game port stays on loopback; 1213 is open at the host firewall
  for launcher direct-connect, but dev Grafana/Prometheus/Loki should
  only be reached via SSH tunnel or local access.
- Don't commit anything from `.data/`.
- Don't propose migrating the production host to NixOS in a passing bead —
  that's a separate architectural decision with hosting/migration cost.
- Don't add services-flake entries that embed real secrets. Dev-only
  literals only.
