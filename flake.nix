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
          # --- Dev-overlay: rewrite host.docker.internal -> localhost in the
          # committed prod prometheus.yml. The string replace is scoped so
          # the file on disk is never mutated — the result lives only in the
          # nix store as prometheus-dev.yml.
          prometheusConfigDev = pkgs.writeText "prometheus-dev.yml" (
            builtins.replaceStrings
              [ "host.docker.internal" ]
              [ "localhost" ]
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
          # ./.data/loki/. Same scoped-replace pattern.
          lokiDataDir = "./.data/loki";
          lokiConfigDev = pkgs.writeText "loki-dev.yml" (
            builtins.replaceStrings
              [ "/loki" ]
              [ lokiDataDir ]
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
              url = "http://localhost:9090";
              isDefault = true;
              editable = false;
              jsonData.timeInterval = "15s";
            }
            {
              name = "Loki";
              type = "loki";
              access = "proxy";
              url = "http://localhost:3100";
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
                port = 5432;
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
                port = 9090;
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
                httpPort = 3100;
                dataDir = lokiDataDir;
                extraFlags = [
                  "-config.file=${lokiConfigDev}"
                ];
              };

              grafana.graf1 = {
                enable = true;
                http_port = 3000;
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
          };
        };
    };
}
