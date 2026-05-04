import { readFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Event source loader for /events and /events.ics.
 *
 * Reads `docs/community/events.yml` at the repo root and parses it
 * into a typed array. The YAML schema is small + controlled (see the
 * top-of-file comment in `events.yml`), so we use a purpose-built
 * mini-parser rather than pulling in the `yaml` npm dependency.
 *
 * Supported subset (intentionally narrow):
 *   - `events:` top-level list
 *   - `- id: slug` entries with scalar fields
 *   - inline `[a, b, c]` arrays for `tags`
 *   - `# comments` and blank lines ignored
 *
 * If the schema ever needs anchors, multi-line strings, or nested
 * mappings we should swap to the `yaml` package — but for the
 * launch-calendar use case this is sufficient and dependency-free.
 */

export type CommunityEvent = {
	id: string;
	title: string;
	start: string;
	end: string;
	description: string;
	tags: string[];
	discordEventId?: string;
};

const EVENTS_PATH = join(
	process.cwd(),
	"..",
	"docs",
	"community",
	"events.yml",
);

/**
 * Strip a trailing `# inline comment` from a value line. We respect
 * `#` inside quoted strings (rare in this file, but worth being
 * correct about).
 */
function stripInlineComment(value: string): string {
	let inSingle = false;
	let inDouble = false;
	for (let i = 0; i < value.length; i++) {
		const ch = value[i];
		if (ch === "'" && !inDouble) inSingle = !inSingle;
		else if (ch === '"' && !inSingle) inDouble = !inDouble;
		else if (ch === "#" && !inSingle && !inDouble) {
			// `#` is only a comment if preceded by whitespace
			// (matches YAML 1.2 — `foo#bar` is a value, not a comment).
			if (i === 0 || /\s/.test(value[i - 1])) {
				return value.slice(0, i).trimEnd();
			}
		}
	}
	return value.trimEnd();
}

function unquote(value: string): string {
	const trimmed = value.trim();
	if (
		(trimmed.startsWith('"') && trimmed.endsWith('"')) ||
		(trimmed.startsWith("'") && trimmed.endsWith("'"))
	) {
		return trimmed.slice(1, -1);
	}
	return trimmed;
}

function parseInlineArray(value: string): string[] {
	const trimmed = value.trim();
	if (!trimmed.startsWith("[") || !trimmed.endsWith("]")) {
		return [];
	}
	const inner = trimmed.slice(1, -1).trim();
	if (!inner) return [];
	return inner
		.split(",")
		.map((item) => unquote(item.trim()))
		.filter((item) => item.length > 0);
}

/**
 * Parse the events.yml subset. Returns the raw entry list — caller
 * is responsible for normalizing into `CommunityEvent`.
 */
function parseEventsYaml(text: string): Record<string, unknown>[] {
	const lines = text.split(/\r?\n/);
	const entries: Record<string, unknown>[] = [];
	let inEventsBlock = false;
	let current: Record<string, unknown> | null = null;

	for (const rawLine of lines) {
		// Drop full-line comments + blank lines first.
		const stripped = stripInlineComment(rawLine);
		if (!stripped.trim()) continue;

		// Top-level `events:` marker.
		if (/^events:\s*$/.test(stripped)) {
			inEventsBlock = true;
			continue;
		}

		if (!inEventsBlock) continue;

		// New entry: `  - key: value`
		const entryStart = stripped.match(/^\s*-\s+(\w+):\s*(.*)$/);
		if (entryStart) {
			if (current) entries.push(current);
			current = {};
			const [, key, value] = entryStart;
			current[key] = parseScalar(key, value);
			continue;
		}

		// Continued field: `    key: value`
		const fieldMatch = stripped.match(/^\s+(\w+):\s*(.*)$/);
		if (fieldMatch && current) {
			const [, key, value] = fieldMatch;
			current[key] = parseScalar(key, value);
		}
	}

	if (current) entries.push(current);
	return entries;
}

function parseScalar(key: string, raw: string): unknown {
	const value = raw.trim();
	if (!value) return "";
	// `tags` is special-cased — it's the only inline-array field.
	if (key === "tags") {
		return parseInlineArray(value);
	}
	return unquote(value);
}

function normalize(entry: Record<string, unknown>): CommunityEvent | null {
	const id = typeof entry.id === "string" ? entry.id : "";
	const title = typeof entry.title === "string" ? entry.title : "";
	const start = typeof entry.start === "string" ? entry.start : "";
	const end = typeof entry.end === "string" ? entry.end : "";
	const description =
		typeof entry.description === "string" ? entry.description : "";
	const tags = Array.isArray(entry.tags)
		? (entry.tags.filter((t) => typeof t === "string") as string[])
		: [];
	const discordEventId =
		typeof entry.discord_event_id === "string"
			? entry.discord_event_id
			: undefined;

	if (!id || !title || !start || !end) return null;
	return { id, title, start, end, description, tags, discordEventId };
}

/**
 * Load all events from the source file. Sorted ascending by start.
 * Build-time call from /events; per-request from /events.ics.
 */
export function loadEvents(): CommunityEvent[] {
	const text = readFileSync(EVENTS_PATH, "utf8");
	const raw = parseEventsYaml(text);
	const events = raw
		.map(normalize)
		.filter((e): e is CommunityEvent => e !== null);
	events.sort((a, b) => a.start.localeCompare(b.start));
	return events;
}

export function partitionByTime(
	events: CommunityEvent[],
	now: Date,
): { upcoming: CommunityEvent[]; past: CommunityEvent[] } {
	const nowIso = now.toISOString();
	const upcoming: CommunityEvent[] = [];
	const past: CommunityEvent[] = [];
	for (const event of events) {
		if (event.end > nowIso) {
			upcoming.push(event);
		} else {
			past.push(event);
		}
	}
	upcoming.sort((a, b) => a.start.localeCompare(b.start));
	past.sort((a, b) => b.start.localeCompare(a.start));
	return { upcoming, past };
}
