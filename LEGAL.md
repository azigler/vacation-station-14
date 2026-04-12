# Legal Info

Authoritative license, attribution, and compliance record for
Vacation Station 14 (VS14). The [README](README.md) has a summary;
this file has the detail.

## Definitions

**Namespace** refers to a subdirectory whose name begins with `_`
(e.g. `_VS`, `_DV`, `_NF`). The prefix declares the upstream fork
authorship of that directory's contents.

**Code** refers to C# source files and compiled assemblies, YAML
files under `Resources/`, and any scripts these may require (e.g.
`Tools/`).

**Assets** refers to sprites, audio, maps, locales, and other
non-code resources under `Resources/`. Assets carry per-file licenses
in neighboring `meta.json` and `attributions.yml` files.

## Copyright

Authors retain all copyright to their respective contributions. They
remain at liberty to contribute their work anywhere else they please.

## License boundary (Flavor A reset, 2026-04-12)

Content contributed to this repository **after** commit
`86a6f6a3bee0c6ac62c1dabfe6e38d79c6c00d2d` — the "Flavor A" clear
commit that rebased VS14 on a pure SS14 base, tagged permanently as
[`flavor-a-baseline-2026-04-12`](https://github.com/azigler/vacation-station-14/releases/tag/flavor-a-baseline-2026-04-12)
— is licensed under the GNU Affero General Public License version
3.0 ([AGPLv3](LICENSE-AGPLv3.txt)) unless explicitly annotated
otherwise.

Content inherited from upstream forks retains its original license
(see the attribution table below). Modifications to upstream-
inherited files — marked with inline `// VS`, `// DV`, `// NF`, etc.
comments — are themselves licensed under AGPLv3.

Pre-Flavor-A commits (Delta-V-inherited + early VS14 authoring) are
captured at the safety tag `pre-flavor-a-clear`. The Delta-V lineage
and its own license mix (MIT + AGPLv3 per Delta-V's legacy
boundary) applies to anything reachable from that tag but not from
HEAD.

## Per-upstream attribution

| Subdirectory | Fork | Repository | License | Mode |
|---|---|---|---|---|
| `_VS/` | Vacation Station 14 (this repo) | [azigler/vacation-station-14](https://github.com/azigler/vacation-station-14) | AGPL-3.0 | authored |
| `Content.*` unprefixed | Space Station 14 | [space-wizards/space-station-14](https://github.com/space-wizards/space-station-14) | MIT (see [LICENSE.TXT](LICENSE.TXT)) | checkout-as-of Phase 1 |
| `RobustToolbox/` (submodule) | RobustToolbox engine | [space-wizards/RobustToolbox](https://github.com/space-wizards/RobustToolbox) | MIT | submodule pin |
| `_DV/` _(pending Phase 5)_ | Delta-V Station | [DeltaV-Station/Delta-v](https://github.com/DeltaV-Station/Delta-v) | AGPL-3.0 + MIT | cherry-pick |

Additional rows added per Phase 5 curation — one row per upstream
we adopt. Until a row is added, that subdirectory does not exist in
this repo.

### Why this pattern

We follow the convention established by
[HardLight Sector](https://github.com/HardLightSector/HardLight):
`git log --follow <path>` combined with the boundary commit SHA is
sufficient to determine the license of any line of code. No
guesswork, no per-file license headers required.

## Per-cherry-pick attribution discipline

When cherry-picking a change from a sibling fork into `_<FORK>/`:

- Preserve the original author in the commit's `Author:` line — do
  not squash into "VS14 import".
- Add a `Co-Authored-By:` trailer for the original author if our
  cherry-pick needed conflict-resolution edits.
- Tag the subsystem in the subject line:
  `cherry-pick: _NF/Bank from new-frontiers-14@abc1234`.
- Reference the VS14 bead that scoped the cherry-pick.
- Record the upstream commit SHA in the body.

This preserves the license chain: a future reader running
`git log --follow Content.Server/_NF/Bank/` sees original Frontier
authors alongside our conflict-resolution commits, each SHA
traceable back to its upstream.

## Code license

The repository as a whole is distributed under the
[AGPLv3](LICENSE-AGPLv3.txt). When AGPLv3 code combines with code
under a more permissive license (MIT, CC-BY-SA, etc.), the combined
work is distributed under AGPLv3 — but the original license text
MUST be preserved in any redistribution.

### Specifically

- **`_VS/` code**: AGPLv3 (original VS14 contributions).
- **`_DV/` code**: AGPLv3 (matches Delta-V's post-boundary license).
- **Unprefixed Content.* code**: MIT (SS14 upstream), sublicensed
  as AGPLv3 when combined with our modifications. Do not remove
  the MIT notice.
- **`_Starlight/` code** (if introduced): custom MIT-like license
  ([LICENSE-Starlight.txt](LICENSE-Starlight.txt)), sublicensed
  as AGPLv3.
- **`RobustToolbox/`**: MIT (Space Wizards Federation engine).

## Asset license

Assets follow the neighboring `meta.json` / `attributions.yml` per
SS14 convention. Most are [CC-BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/).
Some are [CC-BY-NC-SA 3.0](https://creativecommons.org/licenses/by-nc-sa/3.0/)
— the NC (non-commercial) clause forbids monetization of any work
that includes those assets.

VS14's current posture: **no monetization planned**, so CC-BY-NC-SA
assets remain compliant. If monetization is ever adopted, a full
audit + replacement of NC-licensed assets is mandatory before the
monetized version is distributed.

## Per-service deployment obligations

VS14 deploys several third-party services alongside the game server.
Each has its own license + compliance posture:

### AGPLv3 network-service copyleft

Triggers on *public* network interaction — private / LAN deployment
has no obligation. Hub-advertised public server = obligations apply.

Affected: the VS14 game server itself, plus any cherry-picked code
under `_VS/` or `_DV/` licensed AGPLv3, plus bundled services like
ss14-cookbook.

**Compliance**: a "View Source" link to this public repo must be
reachable from each AGPL-deployed service's UI. Configs for every
deployed service live in `ops/` in this repo, so the link + source
parity is automatic.

### MIT attribution only

Affected: SS14.Admin, SS14.MapServer / MapViewer, Robust.Cdn, RSIEdit,
most upstream SS14 pre-boundary code.

**Compliance**: retain each upstream's `LICENSE` file in any local
clone / copy / deployment. Credit on the website's `/credits` page.

### CC-BY-SA 3.0 assets

Must credit the original author; derivatives distributed under the
same license. SS14 convention: `attributions.yml` neighbor file
per-asset.

### CC-BY-NC-SA 3.0 assets

As CC-BY-SA **plus** non-commercial restriction. Compliant as long
as VS14 remains non-monetized.

## Wizards Den OAuth

VS14 uses Wizards Den as identity provider (matches the launcher's
auth flow and SS14 community convention). Wizards Den's policy on
fork / third-party use is referenced here once confirmed.

> **TODO (vs-3tq)**: link + date-stamp Wizden's public permission
> for third-party fork use. Until confirmed, VS14 operates on the
> reasonable inference that fork use is permitted (Delta-V, HardLight,
> and many other forks use Wizden auth); escalate if we hear
> otherwise.

## License / DMCA contact

> **TODO (vs-1ux)**: designated DMCA agent + license-questions email
> + public-facing TOS + privacy policy link here. This is a launch
> blocker for vs-17n (hub advertising).

## Warranty

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
