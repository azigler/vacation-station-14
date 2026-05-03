import type { Metadata } from "next";
import { ContentPage } from "@/components/ContentPage";
import { SiteShell } from "@/components/SiteShell";
import { ServerAddressBox } from "../server-address";

export const metadata: Metadata = {
	title: "Connect — Vacation Station 14",
	description:
		"How to download the SS14 launcher, register a Wizden account, and join Vacation Station 14.",
};

const LAUNCHER_URL = "https://spacestation14.com/about/nightly/";
const ACCOUNT_URL = "https://account.spacestation14.com";

export default function ConnectPage() {
	return (
		<SiteShell>
			<ContentPage
				title="Connect"
				intro={
					<p>
						VS14 runs on the official Space Station 14 launcher. You'll need a
						free Wizden account to play.
					</p>
				}
			>
				<section>
					<h2 className="mt-10 font-display text-3xl leading-tight text-brand-yellow">
						Server address
					</h2>
					<p className="mt-4 font-body text-base leading-relaxed text-brand-white/90 sm:text-lg">
						Once the launcher is installed and signed in, paste this into the{" "}
						<strong className="font-bold text-brand-white">
							Direct Connect
						</strong>{" "}
						dialog (or just search "Vacation Station 14" in the server browser):
					</p>
					<div className="mt-6">
						<ServerAddressBox />
					</div>
				</section>

				<section>
					<h2 className="mt-12 font-display text-3xl leading-tight text-brand-yellow">
						What you need
					</h2>
					<ul className="mt-4 list-disc space-y-2 pl-6 font-body text-base leading-relaxed text-brand-white/90 sm:text-lg">
						<li>
							The official{" "}
							<a
								href={LAUNCHER_URL}
								className="text-brand-yellow underline underline-offset-4 hover:text-brand-white"
							>
								SS14 launcher
							</a>{" "}
							(Windows, macOS, or Linux).
						</li>
						<li>
							A free{" "}
							<a
								href={ACCOUNT_URL}
								className="text-brand-yellow underline underline-offset-4 hover:text-brand-white"
							>
								Wizden account
							</a>{" "}
							— the same one used across hub-listed SS14 servers.
						</li>
					</ul>
				</section>

				<section>
					<h2 className="mt-12 font-display text-3xl leading-tight text-brand-yellow">
						First-time setup
					</h2>
					<ol className="mt-4 list-decimal space-y-3 pl-6 font-body text-base leading-relaxed text-brand-white/90 sm:text-lg">
						<li>
							<strong className="font-bold text-brand-white">
								Download the launcher
							</strong>{" "}
							from{" "}
							<a
								href={LAUNCHER_URL}
								className="text-brand-yellow underline underline-offset-4 hover:text-brand-white"
							>
								spacestation14.com
							</a>
							. The launcher handles content updates per-server, so no manual
							patching.
						</li>
						<li>
							<strong className="font-bold text-brand-white">
								Register a Wizden account
							</strong>{" "}
							at{" "}
							<a
								href={ACCOUNT_URL}
								className="text-brand-yellow underline underline-offset-4 hover:text-brand-white"
							>
								account.spacestation14.com
							</a>
							. Email + password, no extras.
						</li>
						<li>
							<strong className="font-bold text-brand-white">Sign in</strong> to
							the launcher with that account.
						</li>
						<li>
							<strong className="font-bold text-brand-white">
								Find the server
							</strong>{" "}
							in the launcher's server browser — search "Vacation Station 14" —
							or paste the address above into <strong>Direct Connect</strong>.
						</li>
					</ol>
				</section>

				<section>
					<h2 className="mt-12 font-display text-3xl leading-tight text-brand-yellow">
						Troubleshooting
					</h2>
					<ul className="mt-4 list-disc space-y-3 pl-6 font-body text-base leading-relaxed text-brand-white/90 sm:text-lg">
						<li>
							<strong className="font-bold text-brand-white">
								"Authentication required" / connect fails.
							</strong>{" "}
							Sign out of the launcher and back in. VS14 is hub- listed, which
							means Wizden auth is mandatory.
						</li>
						<li>
							<strong className="font-bold text-brand-white">
								Server doesn't show up in the hub list.
							</strong>{" "}
							The hub pings every ~60 seconds; wait a moment and refresh, or
							paste the server address above into{" "}
							<strong>Direct Connect</strong>.
						</li>
						<li>
							<strong className="font-bold text-brand-white">
								Connection blocked.
							</strong>{" "}
							Some firewalls block the SS14 launcher's outbound ports. Allow the
							launcher through your firewall, or try a different network.
						</li>
						<li>
							<strong className="font-bold text-brand-white">
								Stuck on "downloading content."
							</strong>{" "}
							First-time joins pull the server's content build — sit tight, it
							only happens once per content version.
						</li>
					</ul>
				</section>
			</ContentPage>
		</SiteShell>
	);
}
