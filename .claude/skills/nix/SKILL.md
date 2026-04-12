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
| Postgres   | `localhost:5432`        | `vs14 / dev-only-insecure`      |
| Prometheus | `http://localhost:9090` | —                               |
| Loki       | `http://localhost:3100` | —                               |
| Grafana    | `http://localhost:3000` | `admin / admin`                 |

State lives in `.data/` (gitignored). Reset with `rm -rf .data/`.

Dev credentials are literal strings and MUST NOT be reused in prod. The
production stack (vs-3ty postgres, vs-2p3 observability) uses random
passwords loaded from env files / docker secrets.

## When to use which path

| Task                                          | Use                                    |
|-----------------------------------------------|----------------------------------------|
| Local build / run / test                      | nix dev shell                          |
| Contributor onboarding                        | nix + direnv                           |
| CI on GH Actions                              | nix (reproducible)                     |
| Validate `prometheus.yml` / `loki-config.yml` | `promtool` / `loki -verify-config` in the dev shell |
| Spin up postgres for migration testing        | `nix run .#dev-services`               |
| Iterate on a Grafana dashboard                | `nix run .#dev-services`, edit JSON, restart stack |
| Production host bring-up                      | `./setup.ubuntu.sh` + `setup.postgres.sh` + watchdog + docker-compose (see `docs/OPERATIONS.md`) |

The flake is Linux-only (`x86_64-linux` + `aarch64-linux`). `shell.nix`
pulls libdrm/mesa/xorg which don't build on darwin. macOS contributors fall
back to `./setup.ubuntu.sh` on a Linux VM.

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
- Grafana Postgres datasource is **built-in**, not a plugin — don't look for
  it under `grafanaPlugins`.

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

- Don't try to run the dev services stack AND the docker-compose stack on
  the same ports simultaneously. Pick one.
- Don't commit anything from `.data/`.
- Don't propose migrating the production host to NixOS in a passing bead —
  that's a separate architectural decision with hosting/migration cost.
- Don't add services-flake entries that embed real secrets. Dev-only
  literals only.
