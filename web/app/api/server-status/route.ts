import { NextResponse } from "next/server";

/**
 * /api/server-status — proxy SS14 server's /info + /status endpoints
 * with a 15s ISR-style cache (matches `revalidate` + `s-maxage`).
 *
 * Why this route exists: the home-page widget (vs-vw0) needs a clean,
 * shaped JSON payload that combines metadata (desc/links/build) with
 * live state (players/round_id/run_level). The SS14 server splits
 * those across /info and /status, so we fan out and merge.
 *
 * Cache discipline: 15s revalidation prevents request floods even
 * if the home page is hit aggressively. On upstream failure we
 * return 503 with a 5s cache window so transient outages don't
 * pin a bad response for the full 15s window.
 *
 * The upstream URL is fixed to 127.0.0.1:1212 — in dev the SS14
 * server runs locally; in prod the web service runs on the same
 * host as the watchdog, so loopback is reachable.
 */

export const revalidate = 15;

const SS14_BASE = "http://127.0.0.1:1212";
const FETCH_TIMEOUT_MS = 5000;

type Link = {
	name: string;
	icon: string;
	url: string;
};

type Build = {
	engine_version?: string;
	fork_id?: string;
	version?: string;
	// Intentionally NOT surfacing download_url / hash / manifest_*.
	// Those are watchdog/launcher concerns; the website doesn't need them.
};

type ServerStatusPayload = {
	name: string | null;
	desc: string | null;
	players: number | null;
	soft_max_players: number | null;
	round_id: number | null;
	run_level: number | null;
	preset: string | null;
	map: string | null;
	links: Link[];
	build: Build | null;
};

async function fetchWithTimeout(url: string, ms: number): Promise<Response> {
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(), ms);
	try {
		return await fetch(url, {
			signal: controller.signal,
			next: { revalidate: 15 },
		});
	} finally {
		clearTimeout(timer);
	}
}

export async function GET() {
	try {
		const [infoRes, statusRes] = await Promise.all([
			fetchWithTimeout(`${SS14_BASE}/info`, FETCH_TIMEOUT_MS),
			fetchWithTimeout(`${SS14_BASE}/status`, FETCH_TIMEOUT_MS),
		]);

		// /info is the harder requirement — desc + links come from there.
		// /status is best-effort: if it 404s we still return a partial.
		if (!infoRes.ok) {
			throw new Error(`info ${infoRes.status}`);
		}

		const info = (await infoRes.json()) as {
			desc?: string;
			links?: Link[];
			build?: Build;
		};
		const status = statusRes.ok
			? ((await statusRes.json()) as {
					name?: string;
					players?: number;
					soft_max_players?: number;
					round_id?: number;
					run_level?: number;
					preset?: string;
					map?: string | null;
				})
			: {};

		const payload: ServerStatusPayload = {
			name: status.name ?? null,
			desc: info.desc ?? null,
			players: status.players ?? null,
			soft_max_players: status.soft_max_players ?? null,
			round_id: status.round_id ?? null,
			run_level: status.run_level ?? null,
			preset: status.preset ?? null,
			map: status.map ?? null,
			links: info.links ?? [],
			build: info.build
				? {
						engine_version: info.build.engine_version,
						fork_id: info.build.fork_id,
						version: info.build.version,
					}
				: null,
		};

		return NextResponse.json(payload, {
			headers: {
				"Cache-Control": "s-maxage=15, stale-while-revalidate=30",
			},
		});
	} catch (err) {
		return NextResponse.json(
			{ error: "server unreachable", detail: String(err) },
			{
				status: 503,
				headers: { "Cache-Control": "s-maxage=5" },
			},
		);
	}
}
