# ops/nginx — the edge vhost lives in `~/vs14d`, not here

**There is no nginx config in this repo any more.** The public TLS edge for
`vs14.zig.computer` is owned by the operator repo:

```
~/vs14d/ops/nginx/vs14.zig.computer.conf
```

## What was here, and why it went away

This directory used to hold `ss14.zig.computer.conf` — a ~12 KB monolith with
two dozen `location` blocks (`/recipes/`, `/guidebook/`, `/writer/`,
`/nurseshark/`, `/maps/`, `/cdn/`, `/watchdog/`, `/admin/`, `/instances/`,
`/client.zip`) plus an `install.sh` that reinstalled the template and re-ran
certbot.

It was deleted for two reasons that compounded:

1. **The hostname changed.** `ss14.zig.computer` → `vs14.zig.computer`
   (2026-07-26). The cert and the live vhost were cut over out-of-band.
2. **It no longer described production.** The server is tabled. The live edge
   is a small vhost that returns honest `503`s for the game-adjacent paths and
   proxies the apex to the web app. Keeping a stale 12 KB monolith checked in
   next to a live config it disagreed with was a trap, not documentation —
   anyone re-running the old `install.sh` would have clobbered the working edge.

## Why the operator repo owns it

`~/vs14d` is the agentic **operator** for this server — a sibling repo that
holds the pin, the ops surface, and the nightly upstream loop, deliberately
*outside* this 8.5 GB game tree. Edge routing is an operator concern: it
changes on the operator's cadence (cutover, tabling, cert renewal), not the
game content's. Putting it here also made it reachable by a bad rebase of the
very tree the operator exists to rebase.

## Where the per-path `location` blocks went

Also worth knowing before you go looking for `/recipes/`, `/guidebook/`,
`/writer/`, `/nurseshark/`, `/maps/`, `/cdn/` or `/admin/`: the edge vhost no
longer carries them. It proxies `/` to `pico` over the tailnet, and **pico's
own nginx** (`/opt/homebrew/etc/nginx/nginx.conf`) does all the path-specific
routing. The edge keeps only the game-adjacent paths, and those currently
return `503` because the server is tabled.

So the old advice sprinkled through `ops/*/install.sh` and the service READMEs
— "re-run `ops/nginx/install.sh` to publish your location block" — is doubly
dead: the script is gone *and* the block it would have published is not on this
host any more. Those comments now point here instead.

## If you need to change the edge

Edit the vhost in `~/vs14d/ops/nginx/`, then install + reload from there —
never a bare `sudo install` over `/etc/nginx/sites-available/`, which clobbers
certbot's `:443` block (the original vs-15s footgun; the repo copy is
HTTP-only by design). Do not resurrect a vhost in this repo; two sources of
truth for one `server_name` is exactly the failure this deletion removes.

Service-level config that belongs to a *service* (CORS allow-lists, `BaseUrl`,
`AllowedHosts`, `PathBase`) still lives with that service under `ops/<svc>/` —
only the vhost moved.
