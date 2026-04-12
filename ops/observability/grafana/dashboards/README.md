# Grafana dashboards

Dashboard JSON lands here. The Grafana container mounts this directory at
`/var/lib/grafana/dashboards`; the provider config in
`../provisioning/dashboards/dashboards.yml` picks anything dropped in and
surfaces it in the "Vacation Station" folder in the UI.

## Where dashboards come from

Bead **vs-13x** is responsible for authoring the initial dashboards:

- Game server health: player count, tick times, CPU/memory, entity count
- Log panels sourced from Loki (`{App="Robust.Server",Server="vacation-station"}`)
- Watchdog status and restart history
- Postgres / SS14.Admin panels (via the `grafana-postgresql-datasource` plugin)

Until vs-13x lands, this directory is intentionally empty.

## Conventions

- One dashboard per JSON file.
- Filename matches the dashboard `uid` (e.g. `vs14-gameserver.json`).
- Do not commit dashboards with embedded credentials or per-host URLs —
  datasources are referenced by name (`Prometheus`, `Loki`, `Postgres`), which
  Grafana resolves through the provisioned datasource config.
