"use client";

import { useState } from "react";

/**
 * "Connect" widget for the home page hero. Replaces the original
 * `ss14://` deep-link button — that scheme is referenced inside the
 * SS14 engine + hub but the Avalonia-based launcher doesn't reliably
 * register it as an OS-level protocol handler, so clicking the link
 * is a no-op on most platforms.
 *
 * Instead: show the server address in a code box with a one-tap copy
 * button. Users paste it into the launcher's "Direct Connect" dialog.
 *
 * Bead: vs-2dr (post-Phase-1 polish)
 */

const SS14_HOST = "ss14.zig.computer";
const SS14_PORT = 1212;
const SERVER_ADDRESS = `${SS14_HOST}:${SS14_PORT}`;

export function ServerAddressBox() {
	const [copied, setCopied] = useState(false);

	const handleCopy = async () => {
		try {
			await navigator.clipboard.writeText(SERVER_ADDRESS);
			setCopied(true);
			setTimeout(() => setCopied(false), 2000);
		} catch {
			// Clipboard API unavailable (very old browser / non-HTTPS)
			// — silently fail; the address is still visible to read off.
		}
	};

	return (
		<div className="flex flex-col items-center gap-3">
			<div className="flex items-stretch gap-0 rounded-sm border-2 border-brand-yellow bg-brand-blue/40 shadow-[4px_4px_0_0_rgba(220,38,38,1)]">
				<code className="font-mono flex items-center px-4 py-3 text-base text-brand-white sm:text-lg">
					{SERVER_ADDRESS}
				</code>
				<button
					type="button"
					onClick={handleCopy}
					aria-label={copied ? "Copied" : "Copy server address"}
					className="font-display border-l-2 border-brand-yellow bg-brand-yellow px-4 py-3 text-base text-brand-blue transition-colors hover:bg-brand-white focus:outline-none focus:ring-4 focus:ring-brand-yellow/60 sm:text-lg"
				>
					{copied ? "✓ Copied" : "Copy"}
				</button>
			</div>
			<p className="font-body max-w-md text-center text-xs text-brand-white/70 sm:text-sm">
				Paste into the SS14 launcher's <strong>Direct Connect</strong> dialog,
				or search "Vacation Station 14" in the server browser.
			</p>
		</div>
	);
}
