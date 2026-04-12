# Networking — Exposing Vacation Station 14

Covers what ports the server uses, firewall setup, adding a domain name, and HTTPS
via Caddy. Read this before opening your server to the public internet.

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
sudo ufw allow 80/tcp         # HTTP (Caddy, for ACME challenges)
sudo ufw allow 443/tcp        # HTTPS (Caddy)
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
- `TCP 80, 443` from anywhere (if using Caddy)

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

## HTTPS via Caddy (Recommended for Public Servers)

Caddy is a reverse proxy with automatic Let's Encrypt certificates. It's the
simplest way to put HTTPS in front of the SS14 status API.

**Important: Caddy cannot proxy UDP.** The game port (UDP 1212) stays directly
exposed. Caddy only fronts the TCP status API.

### Install Caddy
```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy
```

### Configure Caddy

Edit `/etc/caddy/Caddyfile`:

```
vs14.yourdomain.com {
    reverse_proxy 127.0.0.1:1212
}
```

Reload:
```bash
sudo systemctl reload caddy
```

Caddy will automatically obtain a Let's Encrypt cert on first request to that
hostname. Make sure ports 80 and 443 are open (ACME HTTP-01 challenges use 80).

### Update SS14 config

Bind the status API to localhost (Caddy fronts it):

```toml
[status]
bind = "127.0.0.1:1212"
connectaddress = "udp://vs14.yourdomain.com:1212"

[hub]
advertise = true
server_url = "ss14s://vs14.yourdomain.com"    # ss14s = TLS
```

Note `ss14s://` (with the `s`) in `server_url` — this signals to the launcher
that the status API uses TLS. The UDP game port still uses plain `udp://` in
`connectaddress` because UDP 1212 is still direct.

### Verify

```bash
curl https://vs14.yourdomain.com/info
# Should return the server's JSON info response
```

## Firewall Recipe for Public VS14 Server

```bash
# Host firewall (ufw)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp       # SSH
sudo ufw allow 80/tcp       # Caddy (ACME HTTP-01)
sudo ufw allow 443/tcp      # Caddy (HTTPS status API)
sudo ufw allow 1212/udp     # SS14 game (direct)
sudo ufw enable

# Cloud provider firewall: same rules as above.
# SS14 status API on TCP 1212 stays localhost-only — Caddy fronts it.
```

## Fronting Grafana with Caddy (vs-2p3)

The observability stack (`ops/observability/docker-compose.yml`) binds
Grafana to `127.0.0.1:3000` by design — operators reach it over HTTPS via
Caddy, never directly. The Caddyfile block:

```
grafana.yourdomain.com {
    reverse_proxy 127.0.0.1:3000
}
```

Prerequisites:

- DNS `A` record for `grafana.yourdomain.com` pointing at the host.
- `80/tcp` and `443/tcp` open in ufw and the cloud firewall (ACME HTTP-01
  plus HTTPS).
- Prometheus (`127.0.0.1:9090`) and Loki (`127.0.0.1:3100`) are NOT exposed
  externally and do NOT need a Caddy block — they stay on localhost for
  operator-only debugging via SSH port-forward.
- The SS14 metrics port (`44880/tcp`) stays closed to the public internet;
  Prometheus scrapes it from inside the container over
  `host.docker.internal`. The table above mentions it as "optional", but
  the intended deployment leaves it firewalled.

See `docs/OPERATIONS.md` "Observability" for the full bring-up runbook.

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
- [Caddy docs](https://caddyserver.com/docs/)
- [Let's Encrypt rate limits](https://letsencrypt.org/docs/rate-limits/) (relevant if you renew certs aggressively)
