# SS14.MapViewer — VS14 deployment

Static-mode deployment of [space-wizards/SS14.MapViewer][upstream] under
`https://ss14.zig.computer/maps/`. The frontend is a vanilla Vite build
of the upstream submodule at `external/mapviewer/`; the tiles it renders
are produced locally by `Content.MapRenderer --viewer`.

Part of **vs-236** (parent: **vs-19h**, the ancillary-services decision
matrix).

[upstream]: https://github.com/space-wizards/SS14.MapViewer

## Files

| Path | Purpose |
|---|---|
| `config.json` | MapViewer runtime config (`defaultMap`, `mapListUrl`, `mapDataUrl`). Copied verbatim to the serve root; paths are relative so the app works under the `/maps/` sub-path. |
| `build.sh` | End-to-end pipeline: render maps → build MapViewer (with `--base=/maps/`) → assemble bundle → rsync to `/var/www/vs14-maps/`. Idempotent; see the file header for env overrides. |
| `systemd/vs14-mapviewer-build.service` | One-shot unit that runs `build.sh` as the `ss14` user with appropriate sandboxing. |
| `systemd/vs14-mapviewer-build.timer` | Weekly (Sunday 04:30 UTC) rebuild. |

## Data flow

```
external/mapviewer/  ──npm ci + vite build──▶ <stage>/mapviewer-dist/
                                                     │
Resources/Prototypes/{Maps,_VS/Maps}/*.yml           │
        │                                            │
        ▼                                            ▼
Content.MapRenderer --viewer    +   assemble bundle
        │                                            │
        ▼                                            ▼
<stage>/rendered-maps/<MapId>/       <stage>/bundle/ ──rsync──▶ /var/www/vs14-maps/
  ├─ <MapId>-0.webp                                                   │
  └─ map.json                                                         │
                                                        nginx alias ──┘
                                                        /maps/ → serve root
```

## Install (one-time, as root)

```bash
# 1. Ensure submodule is initialised on the host
cd /opt/vacation-station
git submodule update --init --recursive external/mapviewer

# 2. Create the serve root + scratch dir; own them by the ss14 user
sudo install -d -o ss14 -g ss14 -m 0755 /var/www/vs14-maps /var/cache/vs14-mapviewer

# 3. Install systemd units
sudo cp ops/mapviewer/systemd/vs14-mapviewer-build.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now vs14-mapviewer-build.timer

# 4. (Optional) kick off an immediate first build
sudo systemctl start vs14-mapviewer-build.service
```

The nginx vhost already exposes `/maps/` as an alias of
`/var/www/vs14-maps/` (see `ops/nginx/ss14.zig.computer.conf`).

## Force-rebuild

```bash
sudo systemctl start vs14-mapviewer-build.service
sudo journalctl -u vs14-mapviewer-build.service -f
```

To rebuild a subset of maps locally for testing:

```bash
sudo -u ss14 MAP_LIST="box bagel" /opt/vacation-station/ops/mapviewer/build.sh
```

## Dynamic rendering (deferred)

Upstream MapViewer also supports a MapServer-backed mode (fetch map
metadata from a REST API keyed to GitHub webhooks). That backend is
tracked as a separate, deferred bead — current deployment is static
only:

- **Pros of static**: no runtime service, no DB, no GH App registration,
  no loopback routing. Simpler threat model + lower disk footprint.
- **Cons of static**: tiles only refresh on the weekly timer (or a
  manual kick). Map edits merged mid-week aren't visible on the site
  until the next Sunday rebuild.

Since VS14 maps change on the order of weeks, not hours, the tradeoff
is fine. Revisit when we want PR-preview renders or "merge to main →
map live in minutes" turnaround; at that point, scope a new bead to:

1. Add `external/map-server` submodule + `ops/map-server/` docker-compose
   + appsettings pointing at our repo's `Git.RepositoryUrl`.
2. Route `/maps/api/` through nginx to a loopback port.
3. Swap `ops/mapviewer/config.json` from static (`mapListUrl: maps/list.json`)
   to MapServer-backed URLs (e.g. `/maps/api/maps`).

Until then: static mode. Don't deploy MapServer speculatively.

## Troubleshooting

**No maps in the selector.** Check journal:
```bash
sudo journalctl -u vs14-mapviewer-build.service -n 200
```
Most likely `Content.MapRenderer` silently skipped all of them — usually
a build/link error upstream. Re-run with `SKIP_NPM_INSTALL=1 SKIP_RENDER=0`
and inspect `/var/cache/vs14-mapviewer/rendered-maps/`.

**Stale site.** `rsync --delete-after` only runs after a clean build;
if the build died mid-way the old bundle stays live. That's the
intended failure mode. Force a fresh bundle with:
```bash
sudo rm -rf /var/cache/vs14-mapviewer/bundle
sudo systemctl start vs14-mapviewer-build.service
```

**Asset 404s** (`/maps/assets/*.js` returns a 404). The Vite `--base`
flag must match the nginx sub-path. Both are hard-coded to `/maps/` in
`build.sh` and `ops/nginx/ss14.zig.computer.conf`; if the sub-path ever
moves, update both in lockstep.

**Timer didn't fire.** `systemctl list-timers vs14-mapviewer-build.timer`
should show a next run; if it's empty, the timer was never enabled:
`sudo systemctl enable --now vs14-mapviewer-build.timer`.

## Attribution

MapViewer is MIT-licensed. The upstream `LICENSE` file is retained under
`external/mapviewer/LICENSE` unmodified, satisfying attribution. Tracking
row lives in [`docs/upstream-sync.md`](../../docs/upstream-sync.md).
