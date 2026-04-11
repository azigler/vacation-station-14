# Vacation Station 14

The SS14 server for hanging out.

Vacation Station is a hard fork of [Delta-V Station](https://github.com/DeltaV-Station/Delta-v),
which itself descends from [Space Station 14](https://github.com/space-wizards/space-station-14).
We focus on experimental features, persistence, and community-driven development.

This project is built with AI-assisted development. See our
[contributing guidelines](CONTRIBUTING.md) for details.

## Building

### Dependencies

- [.NET SDK 10](https://dotnet.microsoft.com/download/dotnet/10.0)
- [Python 3.7+](https://www.python.org/) (for initial setup)

### Setup

```bash
git clone https://github.com/azigler/vacation-station-14.git
cd vacation-station-14
git submodule update --init --recursive   # or: python RUN_THIS.py
dotnet build
```

### Running

After building, run the client and server from your IDE, or:

```bash
cd bin/Content.Server && dotnet Content.Server.dll
cd bin/Content.Client && dotnet Content.Client.dll
```

## License

All code after the [fork point](FORK_POINT) in the `_VS` namespace is licensed
under [AGPL-3.0](LICENSE-AGPLv3.txt). Code inherited from upstream is licensed
under [MIT](LICENSE-MIT.txt). See [LEGAL.md](LEGAL.md) for full details.

Most game assets are licensed under [CC-BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/)
unless otherwise noted. Some assets are under CC-BY-NC-SA 3.0 and must be
removed for commercial use. Check `meta.json` and `attributions.yml` files
for individual asset licenses.

## Links

- [Delta-V Station](https://github.com/DeltaV-Station/Delta-v) (upstream fork)
- [Space Station 14](https://github.com/space-wizards/space-station-14) (original project)
- [RobustToolbox](https://github.com/space-wizards/RobustToolbox) (engine)
- [SS14 Developer Docs](https://docs.spacestation14.com/)
