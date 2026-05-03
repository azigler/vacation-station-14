import type { Metadata } from "next";
import { ContentPage } from "@/components/ContentPage";
import { SiteShell } from "@/components/SiteShell";

export const metadata: Metadata = {
	title: "Credits — Vacation Station 14",
	description:
		"Maintainer pointer, upstream attributions, and the contributor list (auto-generated soon).",
};

export default function CreditsPage() {
	return (
		<SiteShell>
			<ContentPage
				title="Credits"
				intro={
					<p>
						VS14 stands on the work of the SS14 community and the sibling forks
						it cherry-picks from.
					</p>
				}
			>
				<section>
					<h2 className="mt-10 font-display text-3xl leading-tight text-brand-yellow">
						Maintainer
					</h2>
					<p className="mt-4 font-body text-base leading-relaxed text-brand-white/90 sm:text-lg">
						Run by a single maintainer —{" "}
						<a
							href="https://github.com/azigler"
							className="text-brand-yellow underline underline-offset-4 hover:text-brand-white"
						>
							azigler on GitHub
						</a>
						.
					</p>
				</section>

				<section>
					<h2 className="mt-12 font-display text-3xl leading-tight text-brand-yellow">
						Upstreams
					</h2>
					<p className="mt-4 font-body text-base leading-relaxed text-brand-white/90 sm:text-lg">
						The base is pure SS14. Curated content lands per-prefix from sibling
						forks:
					</p>
					<ul className="mt-4 list-disc space-y-2 pl-6 font-body text-base leading-relaxed text-brand-white/90 sm:text-lg">
						<li>
							<a
								href="https://github.com/space-wizards/space-station-14"
								className="text-brand-yellow underline underline-offset-4 hover:text-brand-white"
							>
								space-wizards/space-station-14
							</a>{" "}
							— the open-source SS13 successor, the base we fork from.
						</li>
						<li>
							<a
								href="https://github.com/space-wizards/RobustToolbox"
								className="text-brand-yellow underline underline-offset-4 hover:text-brand-white"
							>
								space-wizards/RobustToolbox
							</a>{" "}
							— the engine, pulled as a submodule.
						</li>
						<li>
							The full per-fork attribution table lives in the{" "}
							<a
								href="https://github.com/azigler/vacation-station-14#readme"
								className="text-brand-yellow underline underline-offset-4 hover:text-brand-white"
							>
								repo README
							</a>{" "}
							alongside{" "}
							<a
								href="https://github.com/azigler/vacation-station-14/blob/main/LEGAL.md"
								className="text-brand-yellow underline underline-offset-4 hover:text-brand-white"
							>
								LEGAL.md
							</a>
							.
						</li>
					</ul>
				</section>

				<section>
					<h2 className="mt-12 font-display text-3xl leading-tight text-brand-yellow">
						Contributors
					</h2>
					<p className="mt-4 font-body text-base leading-relaxed text-brand-white/90 sm:text-lg">
						Auto-generated contributor list coming soon. Until then, the{" "}
						<a
							href="https://github.com/azigler/vacation-station-14/graphs/contributors"
							className="text-brand-yellow underline underline-offset-4 hover:text-brand-white"
						>
							GitHub contributors graph
						</a>{" "}
						is the canonical roll.
					</p>
				</section>
			</ContentPage>
		</SiteShell>
	);
}
