import { readFileSync } from "node:fs";
import { join } from "node:path";
import Image from "next/image";
import { ServerStatusCard } from "./server-status";

/**
 * Public home page for Vacation Station 14.
 *
 * Renders as a Server Component so the canonical positioning copy can
 * be inlined at build time from `docs/community/positioning.md` (the
 * SSOT for our identity in words). The live-status card is the only
 * island of interactivity, factored into ./server-status.tsx as a
 * client component.
 *
 * Subsystem refs:
 *   - bead vs-vw0 (vs-2dr.2)
 *   - tagline source: docs/community/positioning.md
 *   - brand tokens: web/app/globals.css @theme
 *   - brand assets: web/public/brand/ (and prepared/ for dept badges)
 */

const SS14_HOST = "ss14.zig.computer";
const SS14_PORT = 1212;
const SS14_LAUNCHER_URI = `ss14://${SS14_HOST}:${SS14_PORT}`;
const GITHUB_URL = "https://github.com/AndrewZigler/vacation-station-14";

// Department badges, displayed under the hero. PNGs live at
// web/public/brand/prepared/badge-<key>.png — height clamped via the
// container row class; widths preserve the painted aspect ratio
// (~600x228 source).
const DEPT_BADGES: ReadonlyArray<{ key: string; label: string }> = [
	{ key: "command", label: "Command" },
	{ key: "security", label: "Security" },
	{ key: "engineering", label: "Engineering" },
	{ key: "medical", label: "Medical" },
	{ key: "science", label: "Science" },
	{ key: "cargo", label: "Cargo" },
	{ key: "service", label: "Service" },
	{ key: "civilian", label: "Civilian" },
];

// Already-served services on the same host — proxied by nginx, NOT
// internal Next.js routes. Use plain <a href> with trailing slashes
// so requests hit nginx, not the Next router.
const TOOLS: ReadonlyArray<{ href: string; label: string; blurb: string }> = [
	{ href: "/recipes/", label: "Cookbook", blurb: "browse recipes" },
	{ href: "/guidebook/", label: "Guidebook", blurb: "in-game wiki" },
	{ href: "/maps/", label: "Maps", blurb: "station blueprints" },
	{ href: "/writer/", label: "Writer", blurb: "lore + fanfic tools" },
	{ href: "/nurseshark/", label: "Nurseshark", blurb: "data dashboards" },
];

// Top-of-page nav. The /rules /about /connect /credits pages are
// owned by vs-u5j; we link to them now so they exist as the routes
// land. GitHub is external.
const NAV_LINKS: ReadonlyArray<{
	href: string;
	label: string;
	external?: boolean;
}> = [
	{ href: "/rules", label: "Rules" },
	{ href: "/about", label: "About" },
	{ href: "/connect", label: "Connect" },
	{ href: "/credits", label: "Credits" },
	{ href: GITHUB_URL, label: "GitHub", external: true },
];

/**
 * Pull the canonical short positioning sentence from the SSOT. When
 * the positioning file is reorganized we fall back to the elevator
 * phrase so the build never breaks on copy edits.
 */
function readPositioningShort(): string {
	const path = join(process.cwd(), "..", "docs", "community", "positioning.md");
	try {
		const md = readFileSync(path, "utf8");
		const shortMatch = md.match(/## Short\n+([\s\S]+?)\n+##/);
		if (!shortMatch) {
			return "A casual SS14 hangout server.";
		}
		const block = shortMatch[1].trim().replace(/\n+/g, " ");
		return block.split(/(?<=[.!?])\s/)[0];
	} catch {
		return "A casual SS14 hangout server.";
	}
}

/**
 * Pull the first paragraph of the long positioning copy — the elevator
 * pitch sub-headline beneath the hero.
 */
function readPositioningElevator(): string {
	const path = join(process.cwd(), "..", "docs", "community", "positioning.md");
	try {
		const md = readFileSync(path, "utf8");
		const longMatch = md.match(/## Long\n+([\s\S]+?)\n+##/);
		if (!longMatch) {
			return "";
		}
		const block = longMatch[1].trim();
		// First paragraph only — split on blank-line boundaries.
		const firstPara = block.split(/\n\s*\n/)[0];
		return firstPara.replace(/\n+/g, " ").trim();
	} catch {
		return "";
	}
}

export default function Home() {
	const tagline = readPositioningShort();
	const elevator = readPositioningElevator();

	return (
		<>
			<TopNav />

			<main className="flex flex-1 flex-col items-center gap-12 px-4 py-8 sm:gap-16 sm:px-6 sm:py-12 lg:py-16">
				{/* Hero */}
				<section
					aria-label="Hero"
					className="flex flex-col items-center gap-6 text-center sm:gap-8"
				>
					<Image
						src="/brand/logo-primary.png"
						alt="Vacation Station 14 logo"
						width={1030}
						height={620}
						priority
						className="h-auto w-full max-w-md sm:max-w-lg lg:max-w-xl"
					/>
					<h1 className="font-display text-4xl leading-tight tracking-wide text-brand-white sm:text-6xl lg:text-7xl">
						Vacation Station 14
					</h1>
					<p className="font-body max-w-2xl text-base leading-relaxed text-brand-white/90 sm:text-lg lg:text-xl">
						{tagline}
					</p>

					{/* Connect CTAs — primary launcher link + secondary instructions */}
					<div className="mt-2 flex flex-col items-center gap-3 sm:flex-row sm:gap-4">
						<a
							href={SS14_LAUNCHER_URI}
							className="font-display inline-block bg-brand-yellow px-8 py-3 text-2xl text-brand-blue shadow-[4px_4px_0_0_rgba(220,38,38,1)] transition-transform hover:translate-x-[-1px] hover:translate-y-[-1px] hover:shadow-[5px_5px_0_0_rgba(220,38,38,1)] focus:outline-none focus:ring-4 focus:ring-brand-yellow/60 sm:text-3xl"
						>
							Connect via Launcher
						</a>
						<a
							href="/connect"
							className="font-body inline-block border-2 border-brand-white/80 px-6 py-3 text-base text-brand-white transition-colors hover:border-brand-yellow hover:text-brand-yellow focus:outline-none focus:ring-4 focus:ring-brand-white/40 sm:text-lg"
						>
							First time? Read setup
						</a>
					</div>

					{/* Address fine-print under the buttons so it's diagnosable
					    even if the launcher protocol isn't installed yet. */}
					<p className="font-body text-xs text-brand-white/60 sm:text-sm">
						<span className="font-bold">Server address:</span>{" "}
						<code className="font-mono">
							{SS14_HOST}:{SS14_PORT}
						</code>
					</p>
				</section>

				{/* Live server status */}
				<section
					aria-label="Server status"
					className="w-full max-w-md sm:max-w-lg"
				>
					<ServerStatusCard />
				</section>

				{/* Dept-badge row — "what kinds of stations live here" */}
				<section
					aria-label="Departments"
					className="flex w-full max-w-5xl flex-col items-center gap-4 sm:gap-6"
				>
					<h2 className="font-display text-2xl text-brand-yellow sm:text-3xl">
						What kinds of stations live here
					</h2>
					<p className="font-body max-w-xl text-center text-sm text-brand-white/80 sm:text-base">
						A curated mix of pure SS14 plus cherry-picks from sibling forks —
						every department gets time on shift.
					</p>
					<ul className="flex flex-wrap items-center justify-center gap-x-4 gap-y-3 sm:gap-x-6 sm:gap-y-4">
						{DEPT_BADGES.map((b) => (
							<li key={b.key} className="flex flex-col items-center gap-1">
								<Image
									src={`/brand/prepared/badge-${b.key}.png`}
									alt={`${b.label} department badge`}
									width={600}
									height={228}
									className="h-5 w-auto"
									sizes="(max-width: 640px) 80px, 120px"
								/>
								<span className="sr-only">{b.label}</span>
							</li>
						))}
					</ul>
				</section>

				{/* Elevator pitch */}
				{elevator && (
					<section
						aria-label="About"
						className="w-full max-w-2xl border-l-4 border-brand-yellow pl-4 sm:pl-6"
					>
						<p className="font-body text-base leading-relaxed text-brand-white/90 sm:text-lg">
							{elevator}
						</p>
					</section>
				)}

				{/* Tools — already-served nginx-proxied services */}
				<section
					aria-label="Tools and services"
					className="flex w-full max-w-3xl flex-col items-center gap-4"
				>
					<h2 className="font-display text-xl text-brand-yellow sm:text-2xl">
						Around the station
					</h2>
					<ul className="flex flex-wrap items-center justify-center gap-2 sm:gap-3">
						{TOOLS.map((t) => (
							<li key={t.href}>
								<a
									href={t.href}
									className="font-body inline-flex items-baseline gap-1 border border-brand-white/40 px-3 py-1.5 text-sm text-brand-white transition-colors hover:border-brand-yellow hover:bg-brand-blue/40 hover:text-brand-yellow sm:text-base"
								>
									<span className="font-bold">{t.label}</span>
									<span className="text-brand-white/60">— {t.blurb}</span>
								</a>
							</li>
						))}
					</ul>
				</section>
			</main>

			<Footer />
		</>
	);
}

function TopNav() {
	return (
		<nav
			aria-label="Primary"
			className="w-full border-b-2 border-brand-yellow/60 bg-brand-blue"
		>
			<div className="mx-auto flex max-w-6xl flex-col items-center gap-2 px-4 py-3 sm:flex-row sm:justify-between sm:gap-4 sm:py-4">
				<a
					href="/"
					className="font-display text-2xl text-brand-yellow transition-colors hover:text-brand-white sm:text-3xl"
				>
					VS14
				</a>
				<ul className="flex flex-wrap items-center justify-center gap-x-4 gap-y-1 sm:gap-x-6">
					{NAV_LINKS.map((link) => (
						<li key={link.href}>
							<a
								href={link.href}
								className="font-display text-lg text-brand-white transition-colors hover:text-brand-yellow sm:text-xl"
								{...(link.external
									? { target: "_blank", rel: "noopener noreferrer" }
									: {})}
							>
								{link.label}
							</a>
						</li>
					))}
				</ul>
			</div>
		</nav>
	);
}

function Footer() {
	return (
		<footer className="mt-12 w-full border-t-2 border-brand-yellow/60 bg-brand-blue/80">
			<div className="mx-auto flex max-w-6xl flex-col items-center gap-2 px-4 py-6 text-center sm:flex-row sm:justify-between sm:text-left">
				<p className="font-body text-sm text-brand-white/80">
					<span className="font-bold">Vacation Station 14</span> — casual
					hangout server.
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
	);
}
