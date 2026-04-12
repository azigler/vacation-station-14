# Grafana dashboards

JSON dashboards provisioned into Grafana on startup. The Grafana container
mounts this directory at `/var/lib/grafana/dashboards`; the provider config
in `../provisioning/dashboards/dashboards.yml` picks anything dropped in
and surfaces it in the "Vacation Station" folder in the UI.

## Shipped dashboards (vs-13x)

| File                  | UID                   | Source                                                                                              |
|-----------------------|-----------------------|-----------------------------------------------------------------------------------------------------|
| `game-servers.json`   | `vs14-game-servers`   | Adapted from upstream SS14 "Game Servers" export                                                    |
| `perf-metrics.json`   | `vs14-perf-metrics`   | Adapted from upstream SS14 "Perf Metrics" export (includes Loki logs panel)                         |

Upstream source for future diffs:
<https://docs.spacestation14.com/en/community/infrastructure-reference/grafana-dashboards.html>
(backed by `space-wizards/docs/src/en/community/infrastructure-reference/grafana-dashboards.md`).

## Adaptations applied on import

- Datasource UIDs rewritten to our provisioned datasource names
  (`Prometheus`, `Loki`, `Postgres`) so Grafana can resolve them without
  the upstream export-time `${DS_…}` input prompts.
- Dashboard `uid` pinned (`vs14-*`) so file-provider updates land in place.
- Dashboard titles prefixed with "Vacation Station"; `vacation-station`
  added to the `tags` list.
- `$Server` template variable rewritten from a hardcoded wizden server
  list to a live `label_values(ss14_round_length{job="gameservers"},
  server)` query, defaulting to `vacation-station`.
- A "Upstream SS14 dashboards" link is added to each dashboard's top-bar
  link list for future diffs.
- `__inputs` / `__elements` / `__requires` / `id` stripped; any
  `libraryPanel` references inlined from `__elements` before strip.

See `docs/OPERATIONS.md` (Observability → Dashboards) for the update and
customisation workflow.

## Conventions

- One dashboard per JSON file.
- Filename matches the dashboard `uid` slug (e.g. `game-servers.json` →
  `vs14-game-servers`).
- Datasources referenced by name (`Prometheus`, `Loki`, `Postgres`), never
  by the auto-generated Grafana uid. Never commit dashboards with embedded
  credentials or per-host URLs.
- When exporting edits from the UI, untick "Export for sharing externally"
  so datasource uids stay bound rather than being templated back into
  `${DS_…}` inputs.
