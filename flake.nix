{
  description = "Development environment for Vacation Station 14";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-25.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
    services-flake.url = "github:juspay/services-flake";
  };

  # Outputs:
  #   - devShells.<system>.default    — same dev shell we always had (shell.nix)
  #   - packages.<system>.dev-services — process-compose entrypoint for the
  #     postgres + prometheus + loki + grafana dev stack. Run with
  #     `nix run .#dev-services`. Data lands in ./.data/ (gitignored).
  #
  # The dev stack reads the SAME configs we committed in ops/observability/
  # (prometheus.yml, loki-config.yml, grafana provisioning). Small in-memory
  # overlays translate docker-specific bits (host.docker.internal, docker
  # secret refs) to localhost/dev-literals without mutating the committed
  # files on disk. See docs/DEVELOPMENT.md for the full story.
  #
  # Port isolation (vs-2f8.7): dev services bind at prod-port + 1 so the
  # two stacks coexist on the same host. Single source of truth below —
  # `devPortOffset = 1` — do NOT hardcode 5433/9091/etc. elsewhere. The
  # SS14 dev game server runs on 1213 (prod 1212) + metrics 44881 (prod
  # 44880). See docs/DEVELOPMENT.md "Running dev on the same box as prod".
  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # Cross-platform: shell.nix branches deps on stdenv (Linux pulls the
      # full client runtime, darwin gets a server-only subset). Windows is
      # not listed — contributors use WSL2 and get the x86_64-linux shell
      # (see docs/DEVELOPMENT.md "Windows (via WSL2)").
      #
      # Note: `packages.dev-services` (the services-flake postgres + prom +
      # loki + grafana stack) is gated to Linux only. services-flake's
      # service modules target Linux process supervision semantics and
      # some of the bundled services (loki, grafana provisioning paths)
      # don't reliably evaluate on darwin. macOS contributors run the
      # docker-compose observability stack instead — see the platform
      # matrix in `.claude/skills/nix/SKILL.md`.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      imports = [
        inputs.process-compose-flake.flakeModule
      ];

      perSystem =
        { pkgs, lib, ... }:
        let
          # --- Port isolation (vs-2f8.7) ---------------------------------
          # Single source of truth for the prod↔dev port offset. Every dev
          # service binds at `prod + devPortOffset` so a dev stack can run
          # alongside the production docker-compose + systemd stack on the
          # same box (e.g. ss14.zig.computer). If you change this constant,
          # every dev port shifts in lockstep — don't spray new ports into
          # the flake by hand.
          devPortOffset = 1;

          # Prod ports (authoritative: ops/observability/docker-compose.yml,
          # instances/vacation-station/config.toml.example, watchdog).
          prodPostgresPort = 5432;
          prodPrometheusPort = 9090;
          prodLokiPort = 3100;
          prodGrafanaPort = 3200;
          prodGamePort = 1212;
          prodMetricsPort = 44880;

          # Dev ports derived from the offset.
          devPostgresPort = prodPostgresPort + devPortOffset; # 5433
          devPrometheusPort = prodPrometheusPort + devPortOffset; # 9091
          devLokiPort = prodLokiPort + devPortOffset; # 3101
          devGrafanaPort = prodGrafanaPort + devPortOffset; # 3201
          devGamePort = prodGamePort + devPortOffset; # 1213
          devMetricsPort = prodMetricsPort + devPortOffset; # 44881

          # --- Dev-overlay: rewrite host.docker.internal -> localhost in the
          # committed prod prometheus.yml. The string replace is scoped so
          # the file on disk is never mutated — the result lives only in the
          # nix store as prometheus-dev.yml.
          #
          # Additionally rewrite the scrape target's metrics port from the
          # prod value (44880) to the dev value (44881) so the in-box dev
          # Prometheus hits the dev SS14 server and not the prod one.
          prometheusConfigDev = pkgs.writeText "prometheus-dev.yml" (
            builtins.replaceStrings
              [
                "host.docker.internal"
                "host.docker.internal:${toString prodMetricsPort}"
              ]
              [
                "localhost"
                "localhost:${toString devMetricsPort}"
              ]
              (builtins.readFile ./ops/observability/prometheus.yml)
          );

          # Wrapper that swaps the services-flake-injected --config.file=...
          # for our dev-overlay YAML. The module builds its flag list as
          #   prometheus --config.file=<generated> --storage.tsdb.path=... ...
          # and duplicate --config.file is a hard error, so we filter the
          # module's flag and re-inject ours before exec. Everything else
          # (--storage.tsdb.path, --web.listen-address, extraFlags) passes
          # through untouched. The derivation pretends to be the prometheus
          # package (it forwards `bin/prometheus` — the only binary the
          # module references via runtimeInputs).
          prometheusWrapped = pkgs.symlinkJoin {
            name = "prometheus-vs14-dev";
            paths = [ pkgs.prometheus ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              rm -f $out/bin/prometheus
              cat > $out/bin/prometheus <<EOF
              #!${pkgs.runtimeShell}
              args=()
              for a in "\$@"; do
                case "\$a" in
                  --config.file=*) ;;  # drop module's auto-injected flag
                  *) args+=("\$a") ;;
                esac
              done
              exec ${pkgs.prometheus}/bin/prometheus \\
                --config.file=${prometheusConfigDev} \\
                "\''${args[@]}"
              EOF
              chmod +x $out/bin/prometheus
            '';
          };

          # Loki prod config uses absolute /loki paths (container FS). In dev
          # we rewrite those to the services-flake dataDir so state lands in
          # ./.data/loki/. We also rewrite the prod http_listen_port (3100,
          # in the config file) to the dev port — services-flake's loki
          # module accepts `httpPort` as a hint but the on-disk config file
          # is what loki actually binds. Without this override loki would
          # bind :3100, collide with the prod docker container, and crash.
          # Same scoped-replace pattern.
          #
          # grpc_listen_port (9096) is rewritten for consistency even though
          # prod's is published only inside the docker bridge — keeps every
          # dev bind at prod+devPortOffset.
          prodLokiGrpcPort = 9096;
          devLokiGrpcPort = prodLokiGrpcPort + devPortOffset; # 9097
          lokiDataDir = "./.data/loki";
          lokiConfigDev = pkgs.writeText "loki-dev.yml" (
            builtins.replaceStrings
              [
                "/loki"
                "http_listen_port: ${toString prodLokiPort}"
                "grpc_listen_port: ${toString prodLokiGrpcPort}"
              ]
              [
                lokiDataDir
                "http_listen_port: ${toString devLokiPort}"
                "grpc_listen_port: ${toString devLokiGrpcPort}"
              ]
              (builtins.readFile ./ops/observability/loki-config.yml)
          );

          # Grafana provisioning: services-flake's grafana module builds its
          # own datasources.yaml from the `datasources` option rather than
          # accepting an external file, so we inline dev equivalents of the
          # entries in ops/observability/grafana/provisioning/datasources/
          # datasources.yml. Docker hostnames become localhost, the docker
          # secret ref ($POSTGRES_PASSWORD) becomes the dev literal.
          #
          # When editing datasources here, also update the prod copy at
          # ops/observability/grafana/provisioning/datasources/datasources.yml.
          # Keep `type` + `jsonData` in sync or dashboards will render
          # "no datasource" in one surface but not the other (vs-3oe).
          #
          # NOTE: the Postgres datasource from prod is intentionally OMITTED
          # here. Dashboards reference `type: grafana-postgresql-datasource`
          # (the plugin), which is not packaged in nixpkgs `grafanaPlugins`,
          # and services-flake's grafana module exposes no runtime
          # plugin-install hook (no `extraEnv`/`GF_INSTALL_PLUGINS` path;
          # only a `declarativePlugins` list of nix-packaged plugins). The
          # options were:
          #   (a) install the plugin at runtime — blocked by the module,
          #   (b) drop Postgres from dev — chosen.
          # Postgres-backed dashboard panels will show "no datasource" in
          # `nix run .#dev-services`; Prometheus + Loki panels work fine.
          # See docs/DEVELOPMENT.md "Dev Services Stack" for the contributor
          # workflow to get Postgres dashboard coverage.
          #
          # Dev-only credentials — do NOT reuse in prod. The prod path uses
          # a 32-byte random postgres password + a separate grafana admin
          # password via docker secrets (see ops/postgres/, ops/observability/).
          devPostgresPassword = "dev-only-insecure";
          devGrafanaAdminPassword = "admin";

          grafanaDatasources = [
            {
              name = "Prometheus";
              type = "prometheus";
              access = "proxy";
              url = "http://localhost:${toString devPrometheusPort}";
              isDefault = true;
              editable = false;
              jsonData.timeInterval = "15s";
            }
            {
              name = "Loki";
              type = "loki";
              access = "proxy";
              url = "http://localhost:${toString devLokiPort}";
              editable = false;
              jsonData.maxLines = 5000;
            }
          ];

          grafanaProviders = [
            {
              name = "vacation-station";
              orgId = 1;
              folder = "Vacation Station";
              type = "file";
              disableDeletion = false;
              updateIntervalSeconds = 30;
              allowUiUpdates = false;
              options = {
                path = ./ops/observability/grafana/dashboards;
                foldersFromFilesStructure = true;
              };
            }
          ];

          # --- Dev SS14 game-server config overlay (vs-2f8.7) --------------
          # Build a dev `config.toml` using the committed prod template as
          # the starting shape, then rewrite:
          #   - [status] bind:    *:1212   -> *:1213
          #   - [metrics] port:   44880    -> 44881
          #   - [database] pg_port: 5432   -> 5433
          #   - [database] pg_password placeholder -> dev literal
          #   - [loki] address: localhost:3100 -> localhost:3101
          #   - [hub] advertise = false stays false (we don't want dev ads
          #     on the public hub even though it could reach the internet)
          # Any fields not matched by the replace table stay identical to
          # prod, which keeps dev parity with the live shape while isolating
          # state and traffic. The overlay lives in the nix store; a runtime
          # wrapper materializes a writable copy under .data/ before the
          # game server reads it.
          ss14ConfigTemplate = builtins.readFile ./instances/vacation-station/config.toml.example;

          ss14ConfigDev = pkgs.writeText "ss14-server-config-dev.toml" (
            builtins.replaceStrings
              [
                "pg_port = ${toString prodPostgresPort}"
                "REPLACE WITH ACTUAL PASSWORD"
                "bind = \"*:${toString prodGamePort}\""
                "port = ${toString prodMetricsPort}"
                "http://localhost:${toString prodLokiPort}"
              ]
              [
                "pg_port = ${toString devPostgresPort}"
                devPostgresPassword
                "bind = \"*:${toString devGamePort}\""
                "port = ${toString devMetricsPort}"
                "http://localhost:${toString devLokiPort}"
              ]
              ss14ConfigTemplate
          );

          # Materialize-overlay runner. process-compose runs this as a
          # one-shot "process" on dev-stack startup; it copies the nix-store
          # overlay into a writable .data/vacation-station/config.toml so
          # the game server can read (and if desired, hot-edit) the dev
          # config without touching /nix/store. The copy is idempotent —
          # running it twice just overwrites the previous dev config, which
          # is the right semantics because flake.nix is the source of truth
          # and any manual in-place edits to .data/.../config.toml between
          # stack starts are by design discarded.
          ss14DevConfigMaterialize = pkgs.writeShellScriptBin "vs14-dev-config-materialize" ''
            set -euo pipefail
            target_dir="./.data/vacation-station"
            target="$target_dir/config.toml"
            mkdir -p "$target_dir"
            install -m 0644 ${ss14ConfigDev} "$target"
            echo "[vs14-dev-config] wrote $target (dev ports: game=${toString devGamePort}, metrics=${toString devMetricsPort}, pg=${toString devPostgresPort}, loki=${toString devLokiPort})"
            echo "[vs14-dev-config] run the dev game server with:"
            echo "[vs14-dev-config]   dotnet run --project Content.Server -- --config-file $target --data-dir .data/vacation-station"
          '';
        in
        {
          devShells.default = import ./shell.nix { inherit pkgs; };

          # services-flake dev stack: Linux only. The process-compose-flake
          # module always registers a `dev-services` package output; we
          # null it out on darwin so `nix flake check --all-systems`
          # doesn't try to evaluate the Linux-specific service modules.
          # Darwin contributors: use `ops/observability/docker-compose.yml`.
          process-compose."dev-services" = lib.mkIf pkgs.stdenv.isLinux {
            imports = [
              inputs.services-flake.processComposeModules.default
            ];

            services = {
              postgres.pg1 = {
                enable = true;
                port = devPostgresPort;
                listen_addresses = "127.0.0.1";
                dataDir = "./.data/postgres";
                initialDatabases = [ { name = "vacation_station"; } ];
                # Dev-only credentials. Prod path uses a 32-byte random
                # password loaded from /etc/vacation-station/postgres.env
                # (see ops/postgres/ + vs-3ty).
                #
                # Split: CREATE USER runs `before` so the role exists when
                # `initialDatabases` creates the DB, but `ALTER DATABASE
                # ... OWNER TO` runs `after` — the DB doesn't exist yet in
                # the before-hook, so chown would fail and the whole pg1
                # service would tear down.
                initialScript.before = ''
                  CREATE USER vs14 WITH PASSWORD '${devPostgresPassword}';
                '';
                initialScript.after = ''
                  ALTER DATABASE vacation_station OWNER TO vs14;
                '';
              };

              prometheus.prom1 = {
                enable = true;
                port = devPrometheusPort;
                listenAddress = "127.0.0.1";
                dataDir = "./.data/prometheus";
                # services-flake's prometheus module auto-generates a
                # --config.file flag from its `extraConfig` attrset. The
                # committed prod config lives as YAML on disk (single
                # source of truth) and we want to use it verbatim (minus
                # the host.docker.internal → localhost overlay), so we
                # can't round-trip through a nix attrset.
                #
                # Adding a second --config.file via extraFlags is rejected
                # by prometheus ("flag 'config.file' cannot be repeated").
                # Solution: wrap the prometheus binary so the module's
                # auto-injected --config.file is swapped for ours before
                # exec. The wrapper is a drop-in `prometheus` package.
                package = prometheusWrapped;
              };

              loki.loki1 = {
                enable = true;
                httpAddress = "127.0.0.1";
                httpPort = devLokiPort;
                dataDir = lokiDataDir;
                extraFlags = [
                  "-config.file=${lokiConfigDev}"
                ];
              };

              grafana.graf1 = {
                enable = true;
                # Dev Grafana uses prod-port + devPortOffset (3201) so it
                # coexists with the prod docker Grafana on 3200 (vs-2f8.7).
                http_port = devGrafanaPort;
                domain = "localhost";
                dataDir = "./.data/grafana";
                datasources = grafanaDatasources;
                providers = grafanaProviders;
                # services-flake only passes `cfg:paths.plugins=<linkFarm>`
                # when declarativePlugins is non-null. With the default
                # `null`, grafana falls back to `<homepath>/data/plugins`,
                # which doesn't exist and produces two startup log lines:
                #   "Failed to get renderer plugin sources"
                #   "Failed to load external plugins"
                # Setting this to an empty list yields an empty linkFarm
                # in /nix/store that grafana can scan cleanly. (vs-2kv)
                declarativePlugins = [ ];
                # Dev-only admin creds. Prod path reads admin password from
                # a docker secret (see ops/observability/docker-compose.yml).
                extraConf = {
                  security = {
                    admin_user = "admin";
                    admin_password = devGrafanaAdminPassword;
                  };
                  analytics.reporting_enabled = false;
                  users.allow_sign_up = false;
                  # Grafana 11+ ships a "preinstall" list that tries to
                  # download bundled plugins (grafana-lokiexplore-app, etc.)
                  # into paths.plugins on first boot. In nix that path lives
                  # read-only under /nix/store, so the install fails noisily.
                  # Disable preinstall — dashboards here don't depend on
                  # those plugins. (Grafana 11.3+ setting.)
                  plugins.preinstall_disabled = true;
                };
              };
            };

            # One-shot: materialize the dev game-server config.toml into
            # .data/vacation-station/ every time the stack boots. The game
            # server itself is NOT launched here (building dotnet + wiring
            # the watchdog-less dev launch is tracked under vs-2f8.7.1);
            # contributors run `dotnet run --project Content.Server -- ...`
            # manually against the materialized config. See
            # docs/DEVELOPMENT.md "Running dev on the same box as prod".
            settings.processes.ss14-dev-config = {
              command = "${ss14DevConfigMaterialize}/bin/vs14-dev-config-materialize";
              availability.restart = "no";
              # Not a long-running service — process-compose marks this
              # Completed after the script exits 0. Keep it first so the
              # config file exists before anyone pokes at the stack.
            };
          };
        };
    };
}
