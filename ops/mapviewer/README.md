# MapViewer (vs-236)

Upstream static frontend: space-wizards/SS14.MapViewer (submodule at
`external/mapviewer/`). Intended to be a zoomable interactive
browser that consumes tile images + `map.json` files from a backend.

## Current status

**Superseded by `ops/map-render/` for first-pass delivery.** That
pipeline runs `Content.MapRenderer --viewer` in a Docker container,
publishes tile images to `/var/www/vs14-maps/rendered/`, and
generates a minimal HTML index at `/var/www/vs14-maps/index.html`.
`/maps/` shows the index; individual tiles are served directly.

The full MapViewer static app is NOT currently built or deployed.
The earlier pipeline (deleted in this commit) drove
Content.MapRenderer directly under systemd and hit the same
TestPair dispose crash that killed the vs-2nk attempt. Once we
want the interactive viewer, the rebuild path is:

1. Point MapViewer's `config.json` at `/maps/api/` (MapServer's
   nginx proxy, which serves map listings + tiles) OR at the
   static output from `ops/map-render/`.
2. `npm ci && npm run build --base=/maps/viewer/` inside
   `external/mapviewer/`, rsync the `dist/` output to
   `/var/www/vs14-maps/viewer/`.
3. Add nginx location `/maps/viewer/` → alias.

This stays in backlog; current `/maps/` index is adequate for v1.

## Files here

- `config.json` — MapViewer runtime config, kept for the future
  rebuild. Points at relative `./maps/` tile paths.
- `README.md` — this file.
