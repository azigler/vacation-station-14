# Vacation Station 14

The SS14 server for hanging out.

Vacation Station 14 (VS14) is a curated
[Space Station 14](https://github.com/space-wizards/space-station-14)
derivative, built with AI-assisted development. The codebase starts from a
pure SS14 base; features from sibling forks (Delta-V, Frontier, Einstein
Engines, etc.) are cherry-picked selectively into directory-prefixed
subsystems (`_VS/`, `_DV/`, `_NF/`, `_SL/`, `_EE/`, …) for clear attribution.

See [contributing guidelines](CONTRIBUTING.md) and [LEGAL.md](LEGAL.md) for
details.

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

See [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) for the full dev-environment
walkthrough (nix is the primary path; `./setup.ubuntu.sh` supports production
hosts).

### Running

After building, run the client and server from your IDE, or:

```bash
cd bin/Content.Server && dotnet Content.Server.dll
cd bin/Content.Client && dotnet Content.Client.dll
```

## Licensing

### License boundary

Content contributed to this repository after commit
`86a6f6a3bee0c6ac62c1dabfe6e38d79c6c00d2d` ("Flavor A" reset, 2026-04-12)
is licensed under the GNU Affero General Public License version 3.0
([AGPLv3](LICENSE-AGPLv3.txt)) unless otherwise annotated.

Content inherited from upstream forks retains its original license (see
attribution table below). Modifications to upstream-inherited files are
marked with inline comments (`// VS`, `// DV`, `// NF`, `// EE`, …) and are
themselves licensed under AGPLv3.

### Upstream attribution

When we pull content from other forks, we organize their work into a
repo-specific subdirectory prefix to make authorship and license
obligations obvious at a glance. Modifications to upstream-inherited files
are denoted by inline `// <FORK>` comments around changed lines.

| Subdirectory | Fork | Repository | License | Mode |
|---|---|---|---|---|
| `_VS/` | Vacation Station 14 (this repo) | [azigler/vacation-station-14](https://github.com/azigler/vacation-station-14) | AGPL-3.0 | authored |
| `Content.*` (unprefixed) | Space Station 14 | [space-wizards/space-station-14](https://github.com/space-wizards/space-station-14) | MIT | checkout-as-of Phase 1 |
| `RobustToolbox/` (submodule) | RobustToolbox engine | [space-wizards/RobustToolbox](https://github.com/space-wizards/RobustToolbox) | MIT | submodule pin |
| `_DV/` _(pending Phase 5)_ | Delta-V Station | [DeltaV-Station/Delta-v](https://github.com/DeltaV-Station/Delta-v) | AGPL-3.0 + MIT | cherry-pick |
| `_NF/` _(pending Phase 5)_ | Frontier Station | [new-frontiers-14/frontier-station-14](https://github.com/new-frontiers-14/frontier-station-14) | AGPL-3.0 + MIT | cherry-pick |
| `_RMC/` _(pending Phase 5)_ | RMC-14 | [RMC-14/RMC-14](https://github.com/RMC-14/RMC-14) | AGPL-3.0 + MIT | cherry-pick |
| `_HL/` _(pending Phase 5)_ | HardLight Sector | [HardLightSector/HardLight](https://github.com/HardLightSector/HardLight) | AGPL-3.0 + MIT | cherry-pick |
| `_SL/` _(pending Phase 5)_ | Starlight | [ss14Starlight/space-station-14](https://github.com/ss14Starlight/space-station-14) | MIT (+ modified-MIT middle period, see LEGAL.md) | cherry-pick |
| `_CP/` _(pending Phase 5)_ | Crystall Punk 14 | [crystallpunk-14/crystall-punk-14](https://github.com/crystallpunk-14/crystall-punk-14) | MIT | cherry-pick |

Bundled services are tracked as submodules under `external/<name>/`
with per-service config under `ops/<name>/`. See [`docs/upstream-sync.md`](docs/upstream-sync.md)
for the full table (cookbook at `/recipes/`, MapViewer + MapServer at
`/maps/`, document-simu at `/writer/`, SS14.Admin at `/admin/`).

Additional cherry-pick sources (Einstein Engines `_EE/`, Corvax `_CX/`)
will be added as remotes when Phase 5 curation targets them.

### Modification convention

Changes to files NOT in an `_<fork>/` subdirectory are annotated inline:

```csharp
// VS - override default value so guests can connect
public const bool AllowGuestConnect = true;

// VS - start
// multi-line block edits get explicit bracket comments
// for easy review + merge-conflict resolution
// VS - end
```

YAML uses `# VS - ...` instead of `// VS - ...`. Same rules for `// DV`,
`// NF`, etc. when cherry-picking a modification from a sibling fork.

### Assets

Most game assets are licensed under
[CC-BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) unless
noted otherwise. Some assets are under CC-BY-NC-SA 3.0 and must be
removed for commercial use. Check each sprite's `meta.json` and
`attributions.yml` for per-asset credit.

See [LEGAL.md](LEGAL.md) for the authoritative per-upstream + per-service
compliance detail.

## Links

- [Space Station 14](https://github.com/space-wizards/space-station-14) (base)
- [RobustToolbox](https://github.com/space-wizards/RobustToolbox) (engine)
- [SS14 Developer Docs](https://docs.spacestation14.com/)
- [Delta-V Station](https://github.com/DeltaV-Station/Delta-v) (sibling fork / cherry-pick source)
- [HardLight Sector](https://github.com/HardLightSector/HardLight) (attribution pattern inspiration)
