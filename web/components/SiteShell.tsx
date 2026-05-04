import Link from "next/link";
import type { ReactNode } from "react";

/**
 * Shared chrome for every page — header (wordmark + dual nav: site
 * pages + tools section) and footer. Used by both the home page and
 * all static content pages so nav stays consistent.
 *
 * The tools section advertises the nginx-proxied services on the
 * same host: cookbook (/recipes/), guidebook (/guidebook/), maps
 * (/maps/), writer (/writer/), nurseshark (/nurseshark/). These
 * are NOT internal Next.js routes — `<a href="...">` deliberately
 * bypasses the App Router so requests hit nginx.
 */

const GITHUB_URL = "https://github.com/azigler/vacation-station-14";

const NAV_PRIMARY: ReadonlyArray<{
	href: string;
	label: string;
	external?: boolean;
}> = [
	{ href: "/rules", label: "Rules" },
	{ href: "/about", label: "About" },
	{ href: "/events", label: "Events" },
	{ href: "/connect", label: "Connect" },
	{ href: GITHUB_URL, label: "GitHub", external: true },
];

const NAV_TOOLS: ReadonlyArray<{ href: string; label: string }> = [
	{ href: "/recipes/", label: "Cookbook" },
	{ href: "/guidebook/", label: "Guidebook" },
	{ href: "/maps/", label: "Maps" },
	{ href: "/writer/", label: "Writer" },
	{ href: "/nurseshark/", label: "Nurseshark" },
];

export function SiteShell({ children }: { children: ReactNode }) {
	return (
		<>
			<header className="border-b-2 border-brand-yellow/60 bg-brand-blue">
				<div className="mx-auto flex w-full max-w-6xl flex-col gap-3 px-4 py-3 sm:flex-row sm:items-start sm:justify-between sm:gap-6 sm:py-4">
					<Link
						href="/"
						className="font-display text-2xl tracking-wide text-brand-yellow transition-colors hover:text-brand-white sm:text-3xl"
					>
						Vacation Station 14
					</Link>
					<nav
						aria-label="Primary"
						className="flex flex-col gap-2 sm:items-end sm:gap-1"
					>
						<ul className="font-display flex flex-wrap items-center gap-x-5 gap-y-1 text-base text-brand-white sm:justify-end sm:text-lg">
							{NAV_PRIMARY.map((link) => (
								<li key={link.href}>
									{link.external ? (
										<a
											href={link.href}
											target="_blank"
											rel="noopener noreferrer"
											className="transition-colors hover:text-brand-yellow"
										>
											{link.label}
										</a>
									) : (
										<Link
											href={link.href}
											className="transition-colors hover:text-brand-yellow"
										>
											{link.label}
										</Link>
									)}
								</li>
							))}
						</ul>
						<ul className="font-body flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-brand-white/75 sm:justify-end">
							<li className="font-display text-xs uppercase tracking-wider text-brand-yellow/80">
								Tools
							</li>
							{NAV_TOOLS.map((tool) => (
								<li key={tool.href}>
									<a
										href={tool.href}
										className="transition-colors hover:text-brand-yellow"
									>
										{tool.label}
									</a>
								</li>
							))}
						</ul>
					</nav>
				</div>
			</header>

			<main className="flex flex-1 flex-col">{children}</main>

			<footer className="border-t-2 border-brand-yellow/60 bg-brand-blue/95">
				<div className="mx-auto flex w-full max-w-6xl flex-col items-center gap-2 px-4 py-6 text-center sm:flex-row sm:justify-between sm:text-left">
					<p className="font-body text-sm text-brand-white/80">
						<span className="font-bold">Vacation Station 14</span> — casual SS14
						hangout. Hub-listed via the Wizards' Den.
					</p>
					<p className="font-body text-xs text-brand-white/60">
						AGPL-3.0 + MIT ·{" "}
						<a
							href={GITHUB_URL}
							target="_blank"
							rel="noopener noreferrer"
							className="text-brand-white/80 underline-offset-2 hover:text-brand-yellow hover:underline"
						>
							source on GitHub
						</a>
					</p>
				</div>
			</footer>
		</>
	);
}
