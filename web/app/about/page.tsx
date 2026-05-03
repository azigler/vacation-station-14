import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { Metadata } from "next";
import { ContentPage } from "@/components/ContentPage";
import { SiteShell } from "@/components/SiteShell";

export const metadata: Metadata = {
	title: "About — Vacation Station 14",
	description:
		"What VS14 is, how the fork is put together, and how to find your way in.",
};

/**
 * /about renders docs/community/about.md verbatim. Source-of-truth
 * lives at the repo root so the Discord welcome, launch announcement,
 * and any future surface inherit the same text.
 */
function readAbout(): string {
	const path = join(process.cwd(), "..", "docs", "community", "about.md");
	const md = readFileSync(path, "utf8");
	return md.replace(/^#\s+.*\n+/, "");
}

export default function AboutPage() {
	const about = readAbout();
	return (
		<SiteShell>
			<ContentPage title="About VS14" markdown={about} />
		</SiteShell>
	);
}
