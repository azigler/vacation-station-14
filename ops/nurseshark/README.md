# ops/nurseshark — Nurseshark static-site deploy (vs-ygn)

Builds and deploys the first-party chemistry/medical/cryo companion
web app at `https://vs14.zig.computer/nurseshark/`.

Source lives in the `external/nurseshark/` submodule
([azigler/nurseshark](https://github.com/azigler/nurseshark), AGPLv3).
Ops config — build pipeline, systemd unit, timer — lives here.

Pattern mirrors `ops/cookbook/` and `ops/guidebook/`: systemd oneshot
runs `build.sh` on a daily timer, static bundle is served by nginx
directly out of the submodule's `dist/` (no `rsync` into
`/var/www/...` — `dist/` is the canonical serve root).

## Files

| File | Purpose |
|---|---|
| `build.sh` | Refreshes VS14 + submodule, runs `npm install && npm run gen && npm run build`, enforces base-path + grep gate. |
| `install.sh` | Installs the systemd unit + timer, enables it, provisions the npm cache dir. |
| `vs14-nurseshark-build.service` | Oneshot unit; runs as `ss14`; points at `build.sh`. |
| `vs14-nurseshark-build.timer` | Daily 05:30 UTC trigger with 15min random delay. |
| `README.md` | This file. |

## First-time install

```bash
sudo ./ops/nurseshark/install.sh         # systemd unit + timer
# nginx: the /nurseshark/ block is not in this repo — see ops/nginx/README.md
sudo systemctl start vs14-nurseshark-build.service
journalctl -u vs14-nurseshark-build.service -f
```

After the first build completes, `curl -I https://vs14.zig.computer/nurseshark/`
should return `200 OK`.

## Critical invariant — VITE_BASE_PATH (vs-ygn.1)

**Every production build MUST set `VITE_BASE_PATH=/nurseshark/`.**

Nurseshark's Vite config reads `process.env.VITE_BASE_PATH` for the
`base` option at build time. Without it, `dist/index.html` references
root-relative `/assets/app.<hash>.js`, which 404s when nginx serves
the bundle under `/nurseshark/`.

`build.sh` enforces this two ways:

1. **Inline set** — the `npm run build` invocation is
   `VITE_BASE_PATH=/nurseshark/ npm run build`. Inline rather than
   `export` so the env var can't leak into a subsequent `npm run dev`.
2. **Post-build grep gate** — after the build, we `grep -q
   /nurseshark/assets/ dist/index.html`. If the base path didn't bake
   in, the build exits non-zero and the previous `dist/` stays live.

Override via `NURSESHARK_BASE_PATH` (systemd `Environment=` or shell
env) if the deploy path ever moves. The grep check uses the same var
so the gate stays in sync.

## nginx (vs-ygn.2)

nginx fronts the static bundle. **The vhost is not in this repo** — the edge
lives at `~/vs14d/ops/nginx/vs14.zig.computer.conf` and the `/nurseshark/`
location block itself is on pico's nginx (see `ops/nginx/README.md`). What
that block does:

- `alias /opt/vacation-station/external/nurseshark/dist/;`
- `try_files $uri $uri/ /nurseshark/index.html;` — SPA fallback so
  BrowserRouter deep-links (`/nurseshark/reagents/Bicaridine`) resolve
  client-side instead of 404-ing.
- Long cache on `/nurseshark/assets/*` — Vite bakes content-hashes
  into filenames, safe for `Cache-Control: public, immutable`.
- Short cache on `/nurseshark/index.html` + `/nurseshark/data/*` —
  daily rebuilds ship fresh content; clients see updates within
  minutes of a build completing.

Edit and reload it where it lives, not here. Don't `install` directly over
`/etc/nginx/sites-available/...` — certbot's `:443` block gets clobbered
(see `vs-15s`).

## Timer cadence

`OnCalendar=*-*-* 05:30:00 UTC`, `RandomizedDelaySec=15min`.

Placed after the morning backup + replay-rotate + cookbook + guidebook
timers:

| Timer | Slot |
|---|---|
| `ss14-backup.timer` | 03:15 UTC |
| replay-rotate | 04:30 UTC |
| `vs14-cookbook-build.timer` | 05:00 UTC |
| `vs14-guidebook-build.timer` | 05:15 UTC |
| **`vs14-nurseshark-build.timer`** | **05:30 UTC** |

## Troubleshooting

### Build failed with "VITE_BASE_PATH did not bake in"

Someone removed the env var from `build.sh` or the Vite config stopped
honoring it. Both:
- Check `NURSESHARK_BASE_PATH` in the build env — `systemctl show
  vs14-nurseshark-build.service | grep Environment`.
- Check `external/nurseshark/vite.config.ts` — the `base` option must
  read `process.env.VITE_BASE_PATH`.
- Don't disable the grep gate as a workaround; fix the underlying
  issue. The gate exists specifically because this invariant is
  silent-on-break otherwise.

### HTTP 404 on a deep-link but 200 on `/nurseshark/`

nginx's `try_files` fallback to `/nurseshark/index.html` is missing.
Fix it where the block lives (pico's nginx — see `ops/nginx/README.md`),
then:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

Confirm with:
```bash
curl -I https://vs14.zig.computer/nurseshark/reagents/Bicaridine   # want 200
```

### Build failed on `git pull`

The service unit runs as `ss14`, which is in the `ubuntu` group and
inherits write access to `/home/ubuntu/vacation-station-14/` via
group bits. If `git pull` fails with permission errors, check the
repo dir is group-writable (`drwxrwxr-x`) and `ss14` is in the owning
group (`groups ss14`).

If a VS14 working-tree dirty state blocks the rebase, the script uses
`git pull --rebase --autostash` — so uncommitted local changes stash
+ reapply automatically. If the reapply conflicts, the script fails
loudly and the previous `dist/` stays served.

### Data is stale / sprites missing

`build.sh` runs `npm run gen` which reads `Resources/` from the VS14
checkout via `sources.yml`. If data looks stale:

1. Confirm the VS14 checkout is current: `git -C /opt/vacation-station
   log -1 --oneline`.
2. Confirm the gen script ran: `ls -la
   /opt/vacation-station/external/nurseshark/public/data/`.
3. Re-run the build manually: `sudo systemctl start
   vs14-nurseshark-build.service` then `journalctl -u
   vs14-nurseshark-build.service -f`.

### nginx serves 500 on assets

Usually a permissions issue — `dist/` is world-readable by default
(`npm run build` produces 0644), but if `umask` is weird on the host
the files might land 0600. Fix:

```bash
sudo chmod -R a+rX /opt/vacation-station/external/nurseshark/dist
```

## Operator notes

- **Submodule bump**: nurseshark's SHA is tracked in VS14. Update
  with `git submodule update --remote external/nurseshark`, commit
  the SHA bump. The timer picks it up on the next run.
- **sources.yml**: written freshly by `build.sh` on each run. It's
  gitignored inside the submodule; no commit discipline to maintain.
- **No separate /var/www/ target**: unlike cookbook / guidebook, we
  serve straight out of `external/nurseshark/dist/`. Saves an rsync,
  but means nginx's alias target IS the build output — don't delete
  the submodule while nginx is up.
