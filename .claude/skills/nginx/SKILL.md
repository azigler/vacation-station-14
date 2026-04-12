---
name: nginx
description: Global nginx reverse proxy — site layout, TLS via certbot, adding a new project vhost, testing + reload discipline
---

# nginx

This host runs a single system-wide nginx as the HTTP(S) edge for
multiple projects. Every project gets one or more vhosts under
`/etc/nginx/sites-available/`, enabled via symlink into
`/etc/nginx/sites-enabled/`. TLS is managed by certbot (Let's Encrypt)
with auto-renewal.

## Layout

```
/etc/nginx/
  nginx.conf                     # core; includes sites-enabled/*
  sites-available/               # all vhost configs live here
    default                      # Debian default (can stay disabled)
    <host>.conf                  # one file per public host
  sites-enabled/                 # symlinks to active vhosts
    <host>.conf -> ../sites-available/<host>.conf
  conf.d/                        # global snippets (rate limits, maps)
  snippets/                      # includable bits (ssl params, headers)
```

Projects should keep the source-of-truth for their own vhost in
their own repo (e.g. `<project>/ops/nginx/<host>.conf`) and either
symlink or `install -m 0644` it into `/etc/nginx/sites-available/`
during deploy.

## Quick reference

```bash
sudo nginx -t                    # validate config; ALWAYS before reload
sudo systemctl reload nginx      # graceful reload (preserves connections)
sudo systemctl restart nginx     # hard restart (drops connections)
sudo tail -f /var/log/nginx/error.log /var/log/nginx/access.log
sudo nginx -T 2>/dev/null | less # dump resolved config (useful for debugging)
```

**Never skip `nginx -t`** before reload. An invalid config that reaches
a reload will return an error; a restart with bad config leaves nginx
off. `-t` catches both cases cheaply.

## Adding a new project vhost

1. Write the vhost in the project repo (e.g. `myproj/ops/nginx/myproj.example.com.conf`).
2. Install into nginx:

```bash
sudo install -m 0644 ./ops/nginx/myproj.example.com.conf \
    /etc/nginx/sites-available/myproj.example.com.conf
sudo ln -sf /etc/nginx/sites-available/myproj.example.com.conf \
    /etc/nginx/sites-enabled/myproj.example.com.conf
sudo nginx -t && sudo systemctl reload nginx
```

3. If it's a new public hostname, either:
   - DNS the host at this server's IP first, THEN
   - `sudo certbot --nginx -d myproj.example.com` — certbot edits the
     vhost in place to add the `listen 443 ssl` block + cert paths.

See the "TLS" section below for the cert flow.

## Minimal vhost template

HTTP-only for initial DNS propagation testing:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name myproj.example.com;

    location / {
        proxy_pass http://127.0.0.1:<BACKEND_PORT>;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_buffering off;
    }
}
```

Path-based routing (one host, multiple backends):

```nginx
server {
    listen 80;
    server_name myproj.example.com;

    # Public download — one narrow path, rewrite-proxy to backend
    location = /client.zip {
        proxy_pass http://127.0.0.1:5000/instances/myproj/binaries/SS14.Client.zip;
    }

    # Admin API — gated by the backend's own auth; HTTPS gives wire protection
    location /admin/ {
        proxy_pass http://127.0.0.1:5000/;
    }

    # Block anything else
    location / {
        return 404;
    }
}
```

## TLS via certbot

```bash
# One-time install
sudo apt-get install -y certbot python3-certbot-nginx

# Issue + install cert for an HTTP-configured vhost
sudo certbot --nginx -d myproj.example.com

# Test renewal (dry-run)
sudo certbot renew --dry-run
```

Certbot installs a systemd timer (`certbot.timer`) that renews certs
twice daily automatically. The timer status is idempotent — safe to
check:

```bash
systemctl list-timers certbot.timer
```

To add a second domain to an existing cert: re-run certbot with the
combined `-d` flags; certbot reissues one multi-SAN cert.

## SSL hardening snippet

Create `/etc/nginx/snippets/ssl-params.conf` once, include from each
vhost after the `listen 443 ssl` line:

```nginx
# In /etc/nginx/snippets/ssl-params.conf:
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
ssl_session_tickets off;
add_header Strict-Transport-Security "max-age=63072000" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
```

Then in each vhost's 443 block:

```nginx
include snippets/ssl-params.conf;
```

## Removing a project

```bash
sudo rm /etc/nginx/sites-enabled/myproj.example.com.conf
# Optional: also remove from sites-available/
sudo nginx -t && sudo systemctl reload nginx

# Revoke the cert
sudo certbot delete --cert-name myproj.example.com
```

## Troubleshooting

| Symptom | Check |
|---|---|
| `nginx -t` says "host not found in upstream" | backend service down, or DNS lookup in a `proxy_pass http://name` instead of an IP |
| 502 Bad Gateway | backend isn't listening on the expected port; check `ss -tlnp` |
| 413 Request Entity Too Large | add `client_max_body_size 100M;` (or as needed) in the vhost `server` block |
| Certbot fails on "Could not connect" | DNS not propagated yet, or ufw blocking 80/443 |
| Config change doesn't take effect | missed a `reload`, or the vhost isn't symlinked into `sites-enabled/` |
| Site intermittently 404s | competing `server_name` in another vhost; `nginx -T \| grep server_name` to find dupes |

## Don't

- Don't edit files directly under `/etc/nginx/sites-available/` if a
  repo owns them — changes will be lost on the next deploy.
- Don't enable a vhost before its DNS has propagated; certbot will fail.
- Don't run `systemctl restart nginx` as a "fix it" reflex; use `-t`
  + `reload` instead. A bad config + restart takes the whole edge down.
- Don't commit the default SSL private key or issued certs to any repo.
  They live at `/etc/letsencrypt/` and stay there.
- Don't manually edit `listen 443 ssl` vhost blocks after certbot has
  shaped them — certbot tracks ownership via comments and will rewrite.
  If you need custom 443 config, structure it via `include` or
  add-on `location` blocks.

## Adopting this skill in a project

Each project that uses nginx should:
1. Keep its vhost config in `ops/nginx/<host>.conf`.
2. Add a deploy script (or at least documentation) that installs the
   vhost into `/etc/nginx/sites-available/` and symlinks into
   `/etc/nginx/sites-enabled/`.
3. Cross-link to this skill from the project's own docs rather than
   duplicating nginx knowledge.

The host is authoritative for live config — the repo is authoritative
for the template. Keep them aligned by having a deploy step that
installs the repo's copy over the host's copy.
