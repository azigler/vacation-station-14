import type { Metadata } from "next";
import { SiteShell } from "@/components/SiteShell";
import {
	type CommunityEvent,
	loadEvents,
	partitionByTime,
} from "./events-source";

export const metadata: Metadata = {
	title: "Events — Vacation Station 14",
	description:
		"Upcoming community events for Vacation Station 14 — launches, special rounds, dev streams, holiday shifts.",
};

/**
 * /events — community calendar.
 *
 * Server Component, reads `docs/community/events.yml` at build time
 * via `loadEvents()`. The same source feeds /events.ics (per-request
 * with edge cache) and — Phase 2, blocked on vs-2l2 — the discord-bot
 * scheduled-event sync.
 *
 * Layout:
 *   - "Upcoming" section: events whose `end` is still in the future,
 *     sorted ascending. Front-and-center.
 *   - "Past" section: events whose `end` has passed, sorted
 *     descending (newest first). Collapsed inside a <details> if
 *     more than 4 entries — keeps the page readable as the archive
 *     grows.
 *
 * Subscribe link points at /events.ics (RFC 5545 VCALENDAR feed)
 * so visitors can pin VS14 events to their own calendar app.
 */

const PAST_COLLAPSE_THRESHOLD = 4;

export default function EventsPage() {
	const events = loadEvents();
	const { upcoming, past } = partitionByTime(events, new Date());

	return (
		<SiteShell>
			<article className="mx-auto w-full max-w-3xl px-6 py-12 sm:py-16">
				<h1 className="font-display text-5xl leading-tight text-brand-white sm:text-6xl">
					Events
				</h1>
				<div className="mt-4 font-body text-lg text-brand-white/90">
					<p>
						Launches, special rounds, dev streams, holiday shifts. Times below
						are in UTC — subscribe to the feed for automatic local-time
						conversion in your calendar app.
					</p>
					<p className="mt-3 text-base text-brand-white/75">
						Subscribe to the feed:{" "}
						<a
							href="/events.ics"
							className="text-brand-yellow underline underline-offset-4 hover:text-brand-white"
						>
							events.ics
						</a>{" "}
						(works with Google Calendar, Apple Calendar, Outlook, and any iCal
						client).
					</p>
				</div>

				<section aria-label="Upcoming events" className="mt-10">
					<h2 className="font-display text-3xl leading-tight text-brand-yellow">
						Upcoming
					</h2>
					{upcoming.length === 0 ? (
						<p className="mt-4 font-body text-base text-brand-white/80 sm:text-lg">
							Nothing on the books right now. Check back soon — or hop into{" "}
							<a
								href="/connect"
								className="text-brand-yellow underline underline-offset-4 hover:text-brand-white"
							>
								Discord
							</a>{" "}
							to hear about events as they get scheduled.
						</p>
					) : (
						<ul className="mt-6 flex flex-col gap-6">
							{upcoming.map((event) => (
								<li key={event.id}>
									<EventCard event={event} />
								</li>
							))}
						</ul>
					)}
				</section>

				<PastEvents events={past} />
			</article>
		</SiteShell>
	);
}

function PastEvents({ events }: { events: CommunityEvent[] }) {
	if (events.length === 0) return null;

	const heading = (
		<h2 className="font-display text-3xl leading-tight text-brand-yellow">
			Past
		</h2>
	);
	const list = (
		<ul className="mt-6 flex flex-col gap-6">
			{events.map((event) => (
				<li key={event.id}>
					<EventCard event={event} dim />
				</li>
			))}
		</ul>
	);

	if (events.length <= PAST_COLLAPSE_THRESHOLD) {
		return (
			<section aria-label="Past events" className="mt-12">
				{heading}
				{list}
			</section>
		);
	}

	return (
		<section aria-label="Past events" className="mt-12">
			<details className="group">
				<summary className="cursor-pointer list-none">
					<div className="flex items-baseline gap-3">
						{heading}
						<span className="font-body text-sm text-brand-white/60">
							{events.length} archived — click to expand
						</span>
					</div>
				</summary>
				{list}
			</details>
		</section>
	);
}

/**
 * Format an ISO 8601 UTC timestamp as a human-readable date+time. We
 * deliberately format on the server in UTC and append `UTC` so the
 * page stays static + cacheable. Visitors who want their local time
 * zone should subscribe via /events.ics — calendar apps localize.
 */
function formatDateTime(iso: string): string {
	const date = new Date(iso);
	const formatter = new Intl.DateTimeFormat("en-US", {
		timeZone: "UTC",
		weekday: "short",
		month: "short",
		day: "numeric",
		year: "numeric",
		hour: "numeric",
		minute: "2-digit",
		hour12: true,
		timeZoneName: "short",
	});
	return formatter.format(date);
}

/**
 * Render a duration like "4h" / "90m" / "2h 30m" / "2 days".
 */
function formatDuration(startIso: string, endIso: string): string {
	const startMs = new Date(startIso).getTime();
	const endMs = new Date(endIso).getTime();
	const totalMinutes = Math.max(0, Math.round((endMs - startMs) / 60000));
	if (totalMinutes < 60) return `${totalMinutes}m`;
	const hours = Math.floor(totalMinutes / 60);
	const minutes = totalMinutes % 60;
	if (hours < 24) {
		if (minutes === 0) return `${hours}h`;
		return `${hours}h ${minutes}m`;
	}
	const days = Math.round(hours / 24);
	return days === 1 ? "1 day" : `${days} days`;
}

function EventCard({
	event,
	dim = false,
}: {
	event: CommunityEvent;
	dim?: boolean;
}) {
	const dateLine = formatDateTime(event.start);
	const duration = formatDuration(event.start, event.end);
	const titleClass = dim
		? "font-display text-2xl text-brand-white/70"
		: "font-display text-2xl text-brand-white";
	const descClass = dim
		? "mt-3 font-body text-base text-brand-white/65 sm:text-lg"
		: "mt-3 font-body text-base text-brand-white/90 sm:text-lg";

	return (
		<article
			className={`border-l-4 ${dim ? "border-brand-white/20" : "border-brand-yellow"} pl-4 sm:pl-6`}
		>
			<h3 className={titleClass}>{event.title}</h3>
			<p className="mt-1 font-body text-sm text-brand-white/70">
				<time dateTime={event.start}>{dateLine}</time>
				<span className="mx-2 text-brand-white/40">·</span>
				<span>{duration}</span>
			</p>
			{event.tags.length > 0 && (
				<ul className="mt-3 flex flex-wrap gap-1.5">
					{event.tags.map((tag) => (
						<li
							key={tag}
							className={`font-body inline-flex items-center border px-2 py-0.5 text-xs uppercase tracking-wider ${
								dim
									? "border-brand-white/20 text-brand-white/55"
									: "border-brand-yellow/50 text-brand-yellow"
							}`}
						>
							{tag}
						</li>
					))}
				</ul>
			)}
			{event.description && <p className={descClass}>{event.description}</p>}
		</article>
	);
}
