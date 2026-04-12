# Networking — Exposing Vacation Station 14

Covers what ports the server uses, firewall setup, adding a domain name, and HTTPS
via nginx. Read this before opening your server to the public internet.

## Default Ports

| Port | Protocol | Purpose | Required for |
|------|----------|---------|--------------|
| 1212 | UDP | Game netcode | All clients |
| 1212 | TCP | HTTP status/info API | Launcher server browser, hub listing |
| 44880 | TCP | Prometheus metrics | Optional, if enabled |

Both 1212 sockets are bound to `0.0.0.0` (all interfaces) by default — they'll be
reachable from any network the host is connected to, subject to firewalls.

## Two Layers of Access Control

Understand these are independent:

### Layer 1: Application binding
Controlled by the app itself. A process bound to `127.0.0.1:N` literally cannot be
reached from outside the host — the kernel has no route. This is the strongest
form of isolation because it's enforced by the app, not a filter.

Check with `sudo ss -tlnp`:
- `127.0.0.1:XXXX` — localhost only, not exposed
- `0.0.0.0:XXXX` or `*:XXXX` — any interface, exposed

### Layer 2: Firewall
Blocks traffic before it reaches the app. Two sub-layers:
- **Host firewall** (ufw on Ubuntu)
- **Cloud provider firewall** (DigitalOcean Cloud Firewall, Hetzner Firewall, AWS Security Group, etc.)

The SS14 server *must* bind publicly (`0.0.0.0`) to be reachable, so firewalls
are your primary defense for unwanted traffic.

## UFW (Uncomplicated Firewall)

UFW is Ubuntu's user-friendly wrapper around the kernel firewall. Default state
is inactive — the kernel accepts traffic on any port that has a listener.

### Check status
```bash
sudo ufw status verbose
```

### Enable with SS14 rules
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp         # SSH
sudo ufw allow 1212/tcp       # SS14 status API
sudo ufw allow 1212/udp       # SS14 game
sudo ufw enable
```

Add these if you use them:
```bash
sudo ufw allow 80/tcp         # HTTP (nginx, for ACME challenges)
sudo ufw allow 443/tcp        # HTTPS (nginx)
sudo ufw allow 44880/tcp      # Prometheus metrics (if enabled)
```

Restrict SSH to a specific IP (recommended if you have a static IP):
```bash
sudo ufw delete allow 22/tcp
sudo ufw allow from <your-ip> to any port 22 proto tcp
```

## Cloud Provider Firewall

Most VPS hosts have a separate firewall in front of the VM. Even with ufw
configured correctly, the cloud firewall can block traffic before it reaches you.

Rules to set (inbound):
- `UDP 1212` from anywhere
- `TCP 1212` from anywhere
- `TCP 22` from your IP (ideally)
- `TCP 80, 443` from anywhere (if using nginx)

Check your provider's control panel:
- **DigitalOcean**: Networking → Cloud Firewalls
- **Hetzner**: Cloud Console → Firewalls
- **AWS EC2**: Security Groups
- **Linode**: Cloud Firewall
- **Vultr**: Products → Firewall

## Testing Reachability

From **another machine** (not the server itself):

```bash
# TCP
nc -zv <vps-ip> 1212

# UDP (slightly harder to test because UDP is connectionless)
nmap -sU -p 1212 <vps-ip>
```

From the SS14 launcher:
- Direct Connect → `<vps-ip>:1212` or `ss14://<vps-ip>`

## Adding a Domain Name

### Step 1: DNS A record

Point a subdomain at the VPS IP:

```
vs14.yourdomain.com.   300   IN   A   <vps-ip>
```

Most registrars (Cloudflare, Namecheap, etc.) have a web UI for this. TTL of
300 seconds (5 min) is fine for development; drop to 60 if you're actively
moving things.

If you use Cloudflare, **disable the orange-cloud proxy for this subdomain**.
Cloudflare only proxies HTTP(S); the UDP game port won't work through it.
Use DNS-only mode (grey cloud).

### Step 2: Tell the server to use the name

Edit `server_config.toml`:

```toml
[status]
connectaddress = "udp://vs14.yourdomain.com:1212"

[hub]
advertise = true
server_url = "ss14://vs14.yourdomain.com"
```

The launcher shows `server_url` in hub listings. Without `connectaddress` the
launcher uses whatever IP the client resolves the status API from, which is
usually fine.

## HTTPS via nginx + certbot

This host runs a system-wide nginx edge for multiple projects (see
`.claude/skills/nginx/SKILL.md` for the general handbook). Per-project
vhosts live in each project's `ops/nginx/`; VS14's lives at
`ops/nginx/ss14.zig.computer.conf` and installs into
`/etc/nginx/sites-available/`.

**What nginx proxies (HTTP/HTTPS only):**
- `/instances/<instance>/binaries/SS14.Client.zip` — launcher client download
- `/client.zip` — short alias for manual testing
- `/admin/` — watchdog admin API (Basic auth with ApiToken, HTTPS wire-wrap)
- `/` — placeholder, reserved for the VS14 website (vs-2dr)

**What nginx does NOT proxy:**
- UDP game traffic (Lidgren) on port 1212 — direct to Robust.Server
- TCP `/info` on port 1212 — SS14 protocol expects `/info` on the game port,
  not a proxied HTTPS endpoint. nginx has nothing to do here.

### Install nginx + certbot (once per host)
```bash
sudo apt install -y nginx certbot python3-certbot-nginx
sudo ufw allow 'Nginx Full'
```

### Install the VS14 vhost
```bash
sudo install -m 0644 ops/nginx/ss14.zig.computer.conf \
    /etc/nginx/sites-available/ss14.zig.computer.conf
sudo ln -sf /etc/nginx/sites-available/ss14.zig.computer.conf \
    /etc/nginx/sites-enabled/ss14.zig.computer.conf
sudo nginx -t && sudo systemctl reload nginx
```

### Issue + install a Let's Encrypt cert
```bash
sudo certbot --nginx -d ss14.zig.computer
```

certbot edits the live vhost at `/etc/nginx/sites-available/...` in place to
add `listen 443 ssl`, cert paths, and an HTTP→HTTPS redirect. The repo copy
stays HTTP-only so nothing sensitive ever reaches source control. Auto-
renewal runs twice daily via the `certbot.timer` systemd unit.

### Update watchdog appsettings.yml

So the `build.download_url` the game server advertises is the HTTPS URL:

```yaml
# /opt/ss14-watchdog/appsettings.yml
BaseUrl: https://ss14.zig.computer/
Urls: http://127.0.0.1:5000   # loopback-only; nginx fronts it
```

Then `sudo systemctl restart ss14-watchdog` and confirm the advertised URL
flipped: `curl http://localhost:1212/info | jq .build.download_url`.

### Close the now-redundant port
```bash
sudo ufw delete allow 5000/tcp
```

### Hub advertising URL

Players connect via:

```
ss14://ss14.zig.computer
```

That's the default `ss14://` scheme on port 1212. `ss14s://` (port 443, TLS-
wrapped handshake) would require running Robust.Server on 443 or a
non-trivial engine config and is not used here.

### Verify

```bash
curl -I https://ss14.zig.computer/client.zip         # 200 + TLS chain valid
curl http://ss14.zig.computer:1212/info              # game-protocol /info, cleartext
curl --max-time 3 http://51.81.33.136:5000/ || echo "refused (expected post-cutover)"
```

## Firewall Recipe for Public VS14 Server

```bash
# Host firewall (ufw)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp       # SSH
sudo ufw allow 80/tcp       # nginx (ACME HTTP-01)
sudo ufw allow 443/tcp      # nginx (HTTPS status API)
sudo ufw allow 1212/udp     # SS14 game (direct)
sudo ufw enable

# Cloud provider firewall: same rules as above.
# SS14 status API on TCP 1212 stays localhost-only — nginx fronts it.
```

## Fronting Grafana with nginx (vs-2p3)

The observability stack (`ops/observability/docker-compose.yml`) binds
Grafana to `127.0.0.1:3200` by design — operators reach it over HTTPS via
nginx, never directly. Vhost pattern:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name grafana.yourdomain.com;

    location / {
        proxy_pass http://127.0.0.1:3200;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Then `sudo certbot --nginx -d grafana.yourdomain.com` to add TLS.

Prerequisites:

- DNS `A` record for `grafana.yourdomain.com` pointing at the host.
- `80/tcp` and `443/tcp` open in ufw and the cloud firewall (ACME HTTP-01
  plus HTTPS).
- Prometheus (`127.0.0.1:9090`) and Loki (`127.0.0.1:3100`) are NOT exposed
  externally and do NOT need a nginx block — they stay on localhost for
  operator-only debugging via SSH port-forward.
- The SS14 metrics port (`44880/tcp`) stays closed to the public internet;
  Prometheus scrapes it from inside the container over
  `host.docker.internal`. The table above mentions it as "optional", but
  the intended deployment leaves it firewalled.

See `docs/OPERATIONS.md` "Observability" for the full bring-up runbook.

## What `ss14://` does and doesn't protect

The SS14 protocol is authenticated but **not encrypted**. Specifically:

**Authenticated:**
- The server's identity — `/info` publishes a `public_key`; the launcher pins
  it and verifies the Lidgren handshake against it. An attacker can't
  successfully impersonate the server without the matching private key.
- Player identity — Wizards Den OAuth issues a signed token over HTTPS to the
  launcher, which presents it during connect. The server verifies the
  signature against Wizden's public key.

**Not encrypted (cleartext on the wire):**
- `/info` responses (HTTP on port 1212)
- Game-state deltas, entity positions, chat messages (Lidgren UDP on 1212)
- Admin commands issued from an in-game console

**Practical implications:**
- Someone sniffing the wire between a player and the server can read chat
  (including OOC and radio), observe entity positions, and see admin commands
  issued from in-game consoles.
- They cannot impersonate the server, modify traffic in flight without
  invalidating the Wizden-signed session, or extract a usable auth token
  that would work against another server.
- Wire sniffing requires a position on the network path — same Wi-Fi as a
  player, a malicious VPN, or an ISP-level observer. Over the open internet
  with TLS-everywhere norms, this is a narrow attack surface in practice.

**Mitigation if it ever becomes a concern:**
- `ss14s://` (TLS-wrapped SS14 handshake on port 443) exists as an engine
  feature. It would require either running Robust.Server on 443 or a
  non-trivial WebSocket-through-nginx config. Not currently deployed; file
  a bead if this becomes necessary (e.g. if VS14 ever hosts sessions where
  chat privacy materially matters).
- Sensitive out-of-band channels (admin coordination, moderation discussions)
  should go through Discord / signal / encrypted messaging, not in-game chat.

This stance matches how most SS14 public servers run — `ss14://` cleartext
game traffic is the community norm; the authentication layer is what players
rely on. The HTTPS pieces (client download, watchdog admin API) we do wrap
in TLS via nginx, because those paths aren't constrained by the game
protocol.

## Common Issues

### Hub advertising fails with "Unable to contact status address"
- The status API isn't reachable from the hub.
- Check firewalls, `connectaddress`, and that `bind` matches what's open.

### Launcher can't connect but Direct Connect works
- TCP 1212 (status API) is blocked, but UDP 1212 (game) isn't.
- Launcher uses TCP to browse; game uses UDP to play.

### Direct Connect fails
- UDP 1212 isn't reachable from outside.
- Cloud provider firewall is the most common culprit.

### "Too many open files" at launch
- Raise `ulimit -n` (consider `LimitNOFILE=65536` in your systemd service).

### Cloudflare orange-cloud breaks the server
- Cloudflare only proxies HTTP(S). UDP traffic can't go through it.
- Switch the subdomain to DNS-only (grey cloud).

## Reference

- [UFW manpage](https://manpages.ubuntu.com/manpages/noble/en/man8/ufw.8.html)
- [nginx docs](https://nginx.org/en/docs/)
- [certbot docs](https://eff-certbot.readthedocs.io/)
- [Let's Encrypt rate limits](https://letsencrypt.org/docs/rate-limits/) (relevant if you renew certs aggressively)
