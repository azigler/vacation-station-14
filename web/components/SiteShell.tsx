import Link from "next/link";
import type { ReactNode } from "react";

/**
 * Shared chrome for content pages — header with site title, simple
 * nav, and a footer line. The home page renders its own hero
 * composition (vs-vw0) and does not use this shell; static content
 * pages (rules / about / connect / credits) all do.
 *
 * Header uses VT323 for the wordmark, body font for nav links.
 * Footer is a single muted line — no marketing footer accordion.
 */

const NAV: ReadonlyArray<{ href: string; label: string }> = [
	{ href: "/", label: "Home" },
	{ href: "/about", label: "About" },
	{ href: "/rules", label: "Rules" },
	{ href: "/connect", label: "Connect" },
	{ href: "/credits", label: "Credits" },
];

export function SiteShell({ children }: { children: ReactNode }) {
	return (
		<>
			<header className="border-b border-brand-white/15 bg-brand-blue/95 backdrop-blur">
				<div className="mx-auto flex w-full max-w-5xl flex-col gap-3 px-6 py-4 sm:flex-row sm:items-center sm:justify-between">
					<Link
						href="/"
						className="font-display text-3xl tracking-wide text-brand-white hover:text-brand-yellow sm:text-4xl"
					>
						Vacation Station 14
					</Link>
					<nav>
						<ul className="flex flex-wrap gap-x-5 gap-y-1 font-body text-base text-brand-white/85">
							{NAV.map((item) => (
								<li key={item.href}>
									<Link
										href={item.href}
										className="underline-offset-4 hover:text-brand-yellow hover:underline"
									>
										{item.label}
									</Link>
								</li>
							))}
						</ul>
					</nav>
				</div>
			</header>

			<main className="flex flex-1 flex-col">{children}</main>

			<footer className="border-t border-brand-white/15 bg-brand-blue/95">
				<div className="mx-auto w-full max-w-5xl px-6 py-4 font-body text-sm text-brand-white/70">
					Vacation Station 14 — a casual SS14 hangout. Hub-listed via the
					Wizards' Den.
				</div>
			</footer>
		</>
	);
}
