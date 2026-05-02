# About VS14

Vacation Station 14 (VS14) is a casual Space Station 14 server. The
30-second pitch lives on the [positioning page](./positioning.md);
this page is the longer story — what kind of project this is, how
the fork is put together, and how to find your way in.

## A low-RP hangout, run as a small project

VS14 is a side project run by a single maintainer — a casual SS14
server built on the premise that the community can use more
chosen-family-style hangout space, less stress-RP, less PvP grind.
The bar for roleplay is participation, not pristine performance.
The bar for time commitment is whatever fits in your week. The
community lives across both Discord and the game; a round is one
of the ways players spend time together, but not the only way.

## How the fork works

VS14 is a fork of [Space Station 14](https://github.com/space-wizards/space-station-14),
the open-source SS13 successor by the Space Wizards Federation. The
base is pure upstream SS14 — we don't carry our own copy of the
engine or the core content. Around that base, we cherry-pick curated
content from sibling forks and stations, each scoped to its own
directory prefix:

- **`_VS/`** — original VS14 content (clothing, recipes, small
  systems written here)
- **`_DV/`** — Delta-V Station picks (mid-RP refinements, cosmetics)
- **`_NF/`** — Frontier Station picks (commerce, exploration)
- **`_RMC/`** — RMC-14 picks (combat, scenario content)
- **`_HL/`** — HardLight Sector picks (a meta-aggregator that itself
  pulls from ~20 forks)
- … and others per [the upstream-sync table](../upstream-sync.md).

Each prefix is both a content boundary and a license boundary — see
[LEGAL.md](../../LEGAL.md) for the full attribution chain. Cherry-
picks land with original-author preservation.

This curated approach is the differentiator. Most SS14 servers run
one upstream's content. VS14 picks the best subsystems from each
and keeps original content small and intentional.

## The community

Three ways to find VS14:

- **In the game** — the server appears on the
  [Wizards' Den hub](https://hub.spacestation14.com/). SS14 launcher
  → server browser → search "Vacation Station 14."
- **In Discord** — link forthcoming once the Discord launches. Most
  of the day-to-day hangout happens here between rounds.
- **On GitHub** —
  [github.com/azigler/vacation-station-14](https://github.com/azigler/vacation-station-14).
  Code, docs, and the task tracker live here.

Players don't need GitHub or Discord accounts to play.

## Contributing

Contributions are welcome:

- **Player feedback** — open a Discord thread or a GitHub issue.
- **Code or content PRs** — see [CONTRIBUTING.md](../../CONTRIBUTING.md)
  for the namespace and attribution rules. We lean fix-merge over
  reject; we'd rather take your idea and finish it than hand it back
  over a missing semicolon.
- **Cherry-pick suggestions** — if a sibling fork shipped something
  you'd like to see here, open a PR or a discussion with the
  upstream SHA.

## License

VS14 inherits SS14 upstream's MIT base, with an AGPLv3 sublicense
layered on at our [Flavor A boundary commit](https://github.com/azigler/vacation-station-14/commit/86a6f6a3bee0c6ac62c1dabfe6e38d79c6c00d2d)
(2026-04-12). New `_VS/` code is AGPLv3. Per-fork subsystem licenses
follow each fork's terms — see [LEGAL.md](../../LEGAL.md) for the
table.

Assets are CC-BY-SA 3.0 unless noted; some content is CC-BY-NC-SA
3.0 (compliant while VS14 stays non-monetized).
