import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { Metadata } from "next";
import { ContentPage } from "@/components/ContentPage";
import { SiteShell } from "@/components/SiteShell";

export const metadata: Metadata = {
	title: "Rules — Vacation Station 14",
	description:
		"Server rules for VS14. Always-on community rules, in-round behavior, command and antag expectations, silicon play.",
};

/**
 * /rules renders docs/community/rules.md verbatim. That file is the
 * SSOT for server rules — same source feeds the in-game MOTD digest
 * and Discord eventually. Stripping the leading H1 happens in the
 * ContentPage h1 override (we render the page title separately).
 */
function readRules(): string {
	const path = join(process.cwd(), "..", "docs", "community", "rules.md");
	const md = readFileSync(path, "utf8");
	// Drop the source's leading "# VS14 server rules" line — the page
	// already shows a title via the ContentPage <h1>. Without this the
	// markdown's first heading would render as a styled <h2> above the
	// rest of the body and read as a redundant second title.
	return md.replace(/^#\s+.*\n+/, "");
}

export default function RulesPage() {
	const rules = readRules();
	return (
		<SiteShell>
			<ContentPage
				title="Server rules"
				intro={
					<p>
						The short version: be kind, stay in character, don't grief. Hit{" "}
						<strong className="text-brand-yellow">F1</strong> in-game to ahelp.
					</p>
				}
				markdown={rules}
			/>
		</SiteShell>
	);
}
