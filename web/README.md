# `web/` — Vacation Station 14 website

Next.js 15 (app router) + bun + Tailwind 4. Brand-integrated from the
ground up — VS14 NES palette and the locked typography pair (VT323
display + Atkinson Hyperlegible body) are wired into the Tailwind theme,
so downstream pages/components inherit by default and don't have to
re-declare branding.

This is the foundation scaffold (vs-2dr.1 / `vs-sv0`). Pages and API
routes land in subsequent vs-2dr beads:

- `vs-vw0` (vs-2dr.2) — home page with hero + connect button + dept-badge row
- `vs-u5j` (vs-2dr.3) — rules / about / connect / credits pages from `docs/community/`
- `vs-a2s` (vs-2dr.4) — `/api/server-status` proxy with 15s cache
- vs-2dr.5 — production deploy

## Dev workflow

Requires `bun` on PATH (the project's nix flake provides it; `direnv
allow` from the repo root activates the env).

```bash
cd web
bun install        # one-time per checkout / after dependency changes
bun run dev        # local dev server on :3300
```

Open http://localhost:3300 — Tailwind classes hot-reload, fonts load
via `next/font` (no extra `<link>` tags), and the landing page pulls
its sub-headline live from `docs/community/positioning.md` at build
time so it stays in sync with the canonical positioning SSOT.

### Why port 3300?

Sequential above the prod-grafana port (3200) so the dev observability
stack (`nix run .#dev-services` — postgres / prometheus / loki /
grafana on :3201–:3203) coexists without collision. Hardcoded in
`package.json` `scripts.dev` and `scripts.start`.

## Build / production

```bash
bun run build      # next build — TS + lint + bundle
bun run start      # next start -p 3300 (serves the build output)
```

### Production deploy

Live at https://vs14.zig.computer/ via the apex `location /` block in the
edge vhost — which lives in the operator repo at
`~/vs14d/ops/nginx/vs14.zig.computer.conf`, not here (see
[`ops/nginx/README.md`](../ops/nginx/README.md)) — and
reverse-proxies to `vs14-web.service` on `127.0.0.1:3300`. The
service is defined at
[`ops/web/vs14-web.service`](../ops/web/vs14-web.service) and runs
`bun run start` as the `ss14` system user with
`WorkingDirectory=/home/ubuntu/vacation-station-14/web` (= `/opt/vacation-station/web`
via the host's `/opt` symlink).

Build output (`web/.next/`) is gitignored — it's regenerated via
[`ops/web/build.sh`](../ops/web/build.sh), which runs
`bun install --frozen-lockfile && bun run build` against the deploy
clone. Both build and service use bun by absolute path
(`/home/ubuntu/.bun/bin/bun`) since the `ss14` user has no shell
profile that would add `~/.bun/bin/` to `PATH`.

**Rebuild + reload after a content change:**

```bash
cd /opt/vacation-station && git pull --rebase
sudo -u ss14 /opt/vacation-station/ops/web/build.sh
sudo systemctl restart vs14-web.service
```

(The `git pull` step is a no-op on the host where `/opt/vacation-station`
is symlinked to the dev checkout — the orchestrator's merge handles
"deploy" implicitly there. Real second-clone hosts run all three.)

**Bring-up from scratch (one-time per host):**

```bash
sudo install -m 0644 ops/web/vs14-web.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo -u ss14 /opt/vacation-station/ops/web/build.sh   # populate web/.next/
sudo systemctl enable --now vs14-web.service
sudo install -m 0644 ~/vs14d/ops/nginx/vs14.zig.computer.conf /etc/nginx/sites-available/
sudo nginx -t && sudo systemctl reload nginx
```

There's no daily timer — the service is a long-running `next start`
process, not a oneshot like the static-site builders. A future bead
may add an automated rebuild-on-`git pull` trigger; for now rebuilds
are an explicit ops gesture.

## Brand integration

| Asset | Location |
|---|---|
| Brand finals (source of truth) | `assets/brand/finals/` (repo root) |
| Brand finals (web public copy) | `web/public/brand/` |
| Visual identity lens (skill) | `.claude/skills/vs14-brand/SKILL.md` |
| Voice / written-content lens | `.claude/skills/vs14-voice/SKILL.md` |

The web copy under `public/brand/` is checked in. When the canonical
`assets/brand/finals/` updates, `cp` the changed file(s) over and
commit the diff — there's no automated symlink, deliberately, so the
served bundle has stable bytes.

### Tailwind theme tokens

Tailwind 4 uses a CSS-first `@theme` block (no `tailwind.config.ts`).
Tokens live in `app/globals.css`:

```css
@theme {
  --color-brand-blue:   #1d4ed8;   /* royal blue */
  --color-brand-yellow: #facc15;   /* mustard yellow */
  --color-brand-red:    #dc2626;   /* vermillion red */
  --color-brand-white:  #ffffff;   /* pixel white */

  --font-display: var(--font-display), monospace;   /* VT323 */
  --font-body:    var(--font-body), sans-serif;     /* Atkinson Hyperlegible */
}
```

Use as utilities: `bg-brand-blue`, `text-brand-yellow`,
`font-display`, `font-body`. The two CSS variable indirection is so
`next/font` can inject a per-instance variable name (set on `<html>`
in `app/layout.tsx`) that the Tailwind token references.

### Typography rules of thumb

- **Display (VT323)**: hero headlines, big section banners, accent
  labels. Single weight only — never fake-bold via stroke. Don't drop
  below ~24px (pixel terminal letters need size).
- **Body (Atkinson Hyperlegible)**: paragraphs, button labels, form
  inputs, microcopy. Reach for 700 weight for emphasis.
- **Anti-pattern**: pairing VT323 with Inter / Roboto / Open Sans —
  defeats the contrast that IS the brand.

Full rules in `.claude/skills/vs14-brand/SKILL.md` § Typography.

## File map

```
web/
├── app/
│   ├── layout.tsx       # Root layout: fonts, body tokens
│   ├── page.tsx         # Landing scaffold (replaced by vs-vw0)
│   └── globals.css      # @import tailwindcss + @theme brand tokens
├── public/
│   └── brand/           # Brand asset copies (logo, badges, prepared/)
├── biome.json           # Enables Tailwind 4 directive parsing for biome
├── next.config.ts
├── package.json         # Scripts override port to 3300
├── postcss.config.mjs   # @tailwindcss/postcss
└── tsconfig.json
```
