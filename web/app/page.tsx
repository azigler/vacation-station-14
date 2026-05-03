import { readFileSync } from "node:fs";
import { join } from "node:path";
import Image from "next/image";

/**
 * Pull the canonical short positioning sentence from
 * docs/community/positioning.md at build time. That file is the SSOT
 * for the server's identity in words — when it changes, downstream
 * surfaces (hub blurb, server browser tag, MOTD, Discord welcome,
 * website hero) all inherit. Reading it here keeps this page in sync
 * automatically without manual copy-paste drift.
 */
function readPositioningShort(): string {
	const path = join(process.cwd(), "..", "docs", "community", "positioning.md");
	const md = readFileSync(path, "utf8");
	const shortMatch = md.match(/## Short\n+([\s\S]+?)\n+##/);
	if (!shortMatch) {
		return "A casual SS14 hangout server.";
	}
	// Take the first sentence — the canonical hub blurb.
	const block = shortMatch[1].trim().replace(/\n+/g, " ");
	const firstSentence = block.split(/(?<=[.!?])\s/)[0];
	return firstSentence;
}

export default function Home() {
	const positioningShort = readPositioningShort();

	return (
		<main className="flex flex-1 flex-col items-center justify-center gap-8 px-6 py-16 text-center">
			<Image
				src="/brand/logo-primary.png"
				alt="Vacation Station 14 logo"
				width={640}
				height={384}
				priority
				className="h-auto w-full max-w-xl"
			/>

			<h1 className="font-display text-5xl leading-tight tracking-wide text-brand-white sm:text-6xl">
				Vacation Station 14
			</h1>

			<p className="font-body max-w-2xl text-lg leading-relaxed text-brand-white/90 sm:text-xl">
				{positioningShort}
			</p>

			<p className="font-display mt-4 text-2xl text-brand-yellow">
				Full home + nav coming via vs-vw0
			</p>
		</main>
	);
}
