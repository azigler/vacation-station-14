# Hosting Vacation Station 14

Levels of hosting commitment, from local dev to full production.

## Level 0 — Local Sandbox (zero setup)

Download prebuilt server zip, install .NET 10 Runtime, run it.

```bash
./setup.ubuntu.sh --runtime
# Download server zip separately
chmod +x Robust.Server
./Robust.Server
# Connect via launcher → Direct Connect → localhost
```

## Level 1 — Invite Friends (LAN/port-forwarded)

Level 0 + port forwarding:
- UDP 1212 (main netcode)
- TCP 1212 (status API)

Edit `server_config.toml`:
```toml
[game]
hostname = "My VS14 Server"

[net]
tickrate = 30

[auth]
mode = 0   # allow guests
```

## Level 2 — Custom Code

Requires dev environment:
```bash
./setup.ubuntu.sh          # full dev setup
dotnet build Content.Packaging -c Release
dotnet run --project Content.Packaging server --hybrid-acz --platform linux-x64
# Output in ./release/
```

**hybrid-acz** means the server serves the client zip to the launcher itself — no separate CDN needed for small deployments.

## Level 3 — "Production" (public, self-hosted)

Level 2 + custom rules + hub advertising.

### Custom rules
Create `Resources/ServerInfo/Guidebook/ServerRules/VacationStationRules.xml` (follow `DefaultRules.xml` format), then:

```toml
[server]
rules_file = "VacationStationRules"
```

### Hub advertising
```toml
[hub]
advertise = true
tags = "roleplay,medium,custom"

[build]
fork_id = "vacation-station"
version = "0.1.0"
download_url = "https://your-host/client.zip"
hash = "<sha256-of-client-zip>"
```

Must be reachable from the outside — port forwarding matters.

## Level 4 — Watchdog (auto-updates + crash recovery)

Install [SS14.Watchdog](https://github.com/space-wizards/SS14.Watchdog). Watchdog runs the game server as a child process and handles:
- Auto-updates from your build publisher
- Crash recovery (automatic restart)
- Admin API (used by wizard-cogs Discord bot)

Requires ASP.NET Core 10 Runtime in addition to .NET Runtime.

## Level 5 — Big Production

Everything above + operational hardening:
- Reverse proxy with HTTPS (nginx + certbot — see `docs/NETWORKING.md`)
- PostgreSQL database (replaces SQLite for shared state)
- Prometheus metrics (port 44880)
- Loki structured logging
- [SS14.Admin](https://github.com/space-wizards/SS14.Admin) web admin panel
- [Robust.Cdn](https://github.com/space-wizards/Robust.Cdn) for client distribution (dozens+ of concurrent players)

### Database switch
```toml
[database]
engine = "postgres"
pg_host = "localhost"
pg_port = 5432
pg_database = "vacation_station"
pg_username = "vs14"
pg_password = "<secret>"
```

Migrations run automatically on server startup.

## Authentication

Most public servers use mode 1 (auth required):
```toml
[auth]
mode = 1   # all clients need a Wizards Den account
```

No server-side secrets needed for default auth (uses central.spacestation14.io).

## Admin Bootstrapping

First admin setup:
```toml
[console]
loginlocal = true              # localhost auto-grants +HOST
login_host_user = "your-account"   # this account becomes +HOST on connect
```

Or promote a currently-connected user from the server stdin:
```
promotehost <username>
```

**+HOST is effectively full server control. Don't give it casually.**

## Related Services

- [SS14.Watchdog](https://github.com/space-wizards/SS14.Watchdog) — server supervisor (Level 4+)
- [SS14.Admin](https://github.com/space-wizards/SS14.Admin) — web admin panel (Level 5)
- [Robust.Cdn](https://github.com/space-wizards/Robust.Cdn) — client CDN (Level 5, scale)
- [wizard-cogs](https://github.com/space-wizards/wizard-cogs) — Discord bot cogs
- [SS14.Changelog](https://github.com/space-wizards/SS14.Changelog) — PR changelog automation

## Useful Environment Variables

Performance tuning for servers:
```bash
export DOTNET_TieredPGO=1
export DOTNET_TC_QuickJitForLoops=1
export DOTNET_ReadyToRun=0
export ROBUST_NUMERICS_AVX=true
```

libssl version override if needed:
```bash
export CLR_OPENSSL_VERSION_OVERRIDE=48
```

## References

- [Official SS14 hosting docs](https://docs.spacestation14.com/en/general-development/setup/server-hosting-tutorial.html)
- [Config file reference](https://docs.spacestation14.com/en/general-development/tips/server-config.html)
- [Public hub server rules](https://docs.spacestation14.com/en/community/space-wizards-hub-rules.html)
