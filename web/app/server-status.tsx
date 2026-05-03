"use client";

import { useEffect, useState } from "react";

/**
 * Shape of /api/server-status (vs-a2s). Lands in parallel — until then
 * any non-200 response (including 404) shows the static fallback.
 *
 * Keep this loose: real schema lives in vs-a2s. We pluck only the few
 * fields the home page surfaces today, so a richer schema later won't
 * force a coupled change here.
 */
type ServerStatus = {
	players?: number;
	soft_max_players?: number;
	round_id?: number;
	map?: string;
	name?: string;
};

const POLL_MS = 15_000;
const ENDPOINT = "/api/server-status";

export function ServerStatusCard() {
	const [status, setStatus] = useState<ServerStatus | null>(null);
	const [loaded, setLoaded] = useState(false);

	useEffect(() => {
		let cancelled = false;

		async function fetchStatus() {
			try {
				const res = await fetch(ENDPOINT, { cache: "no-store" });
				if (!res.ok) {
					if (!cancelled) {
						setStatus(null);
						setLoaded(true);
					}
					return;
				}
				const data = (await res.json()) as ServerStatus;
				if (!cancelled) {
					setStatus(data);
					setLoaded(true);
				}
			} catch {
				if (!cancelled) {
					setStatus(null);
					setLoaded(true);
				}
			}
		}

		fetchStatus();
		const id = setInterval(fetchStatus, POLL_MS);
		return () => {
			cancelled = true;
			clearInterval(id);
		};
	}, []);

	// Static fallback — the API isn't live yet, or returned an error.
	// Every visitor sees this gracefully on first paint until vs-a2s lands.
	if (!loaded || !status) {
		return (
			<aside
				aria-label="Server status"
				className="border-2 border-brand-yellow/60 bg-brand-blue/40 px-6 py-5 text-left shadow-[4px_4px_0_0_rgba(250,204,21,0.4)]"
			>
				<p className="font-display text-2xl text-brand-yellow">
					Live status coming soon
				</p>
				<p className="font-body mt-1 text-sm text-brand-white/80">
					Connect via the launcher to see who&apos;s on shift right now.
				</p>
			</aside>
		);
	}

	const players = typeof status.players === "number" ? status.players : null;
	const cap =
		typeof status.soft_max_players === "number"
			? status.soft_max_players
			: null;
	const map = status.map ?? null;
	const round = typeof status.round_id === "number" ? status.round_id : null;

	return (
		<aside
			aria-label="Server status"
			className="border-2 border-brand-yellow bg-brand-blue/40 px-6 py-5 text-left shadow-[4px_4px_0_0_rgba(250,204,21,0.6)]"
		>
			<div className="flex items-baseline gap-3">
				<span
					aria-hidden="true"
					className="inline-block h-3 w-3 rounded-full bg-brand-yellow"
				/>
				<p className="font-display text-2xl text-brand-yellow">Live now</p>
			</div>
			<dl className="font-body mt-2 grid grid-cols-2 gap-x-4 gap-y-1 text-sm text-brand-white">
				{players !== null && (
					<>
						<dt className="text-brand-white/70">Players</dt>
						<dd className="font-bold">
							{players}
							{cap !== null ? ` / ${cap}` : ""}
						</dd>
					</>
				)}
				{map && (
					<>
						<dt className="text-brand-white/70">Map</dt>
						<dd className="font-bold">{map}</dd>
					</>
				)}
				{round !== null && (
					<>
						<dt className="text-brand-white/70">Round</dt>
						<dd className="font-bold">#{round}</dd>
					</>
				)}
			</dl>
		</aside>
	);
}
