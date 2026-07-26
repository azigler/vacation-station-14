import { loadEvents } from "../events/events-source";

/**
 * /events.ics — RFC 5545 VCALENDAR feed of VS14 community events.
 *
 * Same source-of-truth as /events (`docs/community/events.yml`).
 * Per-request rendering with a 5-minute edge cache (`s-maxage=300`)
 * — cheap to regenerate, no need to rebuild the site to push new
 * events to subscribers.
 *
 * Why a route handler and not a static asset: events.yml lives at
 * the repo root, so generating at request time keeps the source +
 * feed in lockstep without a build step or pre-render trick. The
 * cache header takes care of cost.
 *
 * UID format: `vs14-<slug>@ss14.zig.computer`. Stable across edits
 * — that's the contract that lets calendar apps update events in
 * place rather than duplicating them.
 *
 * DO NOT rewrite the `ss14.zig.computer` in UID_DOMAIN to the current
 * public hostname (`vs14.zig.computer`, cut over 2026-07-26). An
 * iCalendar UID is an opaque permanent identifier, not a URL — RFC 5545
 * only requires global uniqueness, and nothing ever resolves it. Change
 * it and every already-subscribed calendar sees a brand-new event and
 * duplicates the entire feed. The domain part is frozen at the value it
 * was first published under, deliberately and permanently.
 *
 * Date format: VCALENDAR uses `YYYYMMDDTHHMMSSZ` (no dashes, no
 * colons). We convert from ISO 8601 in `formatICalDate`.
 *
 * Line-folding: per RFC 5545 lines longer than 75 octets must be
 * folded. The descriptions we emit are short enough that we can
 * skip folding for now — if we ever exceed 75 octets we'll need
 * to fold (CRLF + space) on the wire.
 */

export const dynamic = "force-dynamic";

const PRODID = "-//Vacation Station 14//Community Events//EN";
// Frozen on purpose — see the UID note in the module docblock above.
const UID_DOMAIN = "ss14.zig.computer";

/**
 * RFC 5545 escape: backslash, semicolon, comma, and newlines must
 * be escaped inside TEXT-typed properties (SUMMARY, DESCRIPTION,
 * LOCATION).
 */
function escapeText(value: string): string {
	return value
		.replace(/\\/g, "\\\\")
		.replace(/;/g, "\\;")
		.replace(/,/g, "\\,")
		.replace(/\r?\n/g, "\\n");
}

/**
 * ISO 8601 (`2026-06-01T22:00:00Z`) → VCALENDAR
 * (`20260601T220000Z`). Strips dashes, colons, and milliseconds.
 */
function formatICalDate(iso: string): string {
	const date = new Date(iso);
	const yyyy = date.getUTCFullYear().toString().padStart(4, "0");
	const mm = (date.getUTCMonth() + 1).toString().padStart(2, "0");
	const dd = date.getUTCDate().toString().padStart(2, "0");
	const hh = date.getUTCHours().toString().padStart(2, "0");
	const mi = date.getUTCMinutes().toString().padStart(2, "0");
	const ss = date.getUTCSeconds().toString().padStart(2, "0");
	return `${yyyy}${mm}${dd}T${hh}${mi}${ss}Z`;
}

export function GET() {
	const events = loadEvents();
	const dtstamp = formatICalDate(new Date().toISOString());

	const lines: string[] = [
		"BEGIN:VCALENDAR",
		"VERSION:2.0",
		`PRODID:${PRODID}`,
		"CALSCALE:GREGORIAN",
		"METHOD:PUBLISH",
		"X-WR-CALNAME:Vacation Station 14",
		"X-WR-CALDESC:Community events for VS14 — launches, special rounds, holiday shifts.",
		"X-WR-TIMEZONE:UTC",
	];

	for (const event of events) {
		const uid = `vs14-${event.id}@${UID_DOMAIN}`;
		lines.push(
			"BEGIN:VEVENT",
			`UID:${uid}`,
			`DTSTAMP:${dtstamp}`,
			`DTSTART:${formatICalDate(event.start)}`,
			`DTEND:${formatICalDate(event.end)}`,
			`SUMMARY:${escapeText(event.title)}`,
		);
		if (event.description) {
			lines.push(`DESCRIPTION:${escapeText(event.description)}`);
		}
		if (event.tags.length > 0) {
			// CATEGORIES is a comma-separated list per RFC 5545. We
			// escape each tag individually so commas inside a tag
			// survive (rare, but safe).
			const cats = event.tags.map(escapeText).join(",");
			lines.push(`CATEGORIES:${cats}`);
		}
		lines.push("END:VEVENT");
	}

	lines.push("END:VCALENDAR");

	// RFC 5545 mandates CRLF line endings.
	const body = `${lines.join("\r\n")}\r\n`;

	return new Response(body, {
		headers: {
			"Content-Type": "text/calendar; charset=utf-8",
			"Cache-Control": "s-maxage=300",
		},
	});
}
