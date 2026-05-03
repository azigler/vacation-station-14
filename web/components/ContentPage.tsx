import type { ReactNode } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";

/**
 * Renders a markdown string as VS14-styled content.
 *
 * Headings get the display font (VT323); body, lists, and code stay
 * in Atkinson Hyperlegible. Links pick up the brand yellow with an
 * underline. Layout is a centered max-width column so long paragraphs
 * don't overflow on wide screens.
 *
 * Used by /rules, /about, and any future markdown-backed page. For
 * pages whose content is not a single markdown file (e.g. /connect,
 * /credits) just compose the same shell + your own children — see
 * the `intro` and `children` props.
 */
export function ContentPage({
	title,
	intro,
	markdown,
	children,
}: {
	title: string;
	intro?: ReactNode;
	markdown?: string;
	children?: ReactNode;
}) {
	return (
		<article className="mx-auto w-full max-w-3xl px-6 py-12 sm:py-16">
			<h1 className="font-display text-5xl leading-tight text-brand-white sm:text-6xl">
				{title}
			</h1>
			{intro ? (
				<div className="mt-4 font-body text-lg text-brand-white/90">
					{intro}
				</div>
			) : null}

			<div className="mt-8">
				{markdown ? (
					<ReactMarkdown
						remarkPlugins={[remarkGfm]}
						components={{
							// The source markdown's leading H1 duplicates the
							// page title we render above — drop it so the
							// rendered page doesn't have two H1s. Subsequent
							// H1s (rare in the source) demote to H2 styling.
							h1: ({ children }) => (
								<h2 className="mt-10 font-display text-4xl leading-tight text-brand-white">
									{children}
								</h2>
							),
							h2: ({ children }) => (
								<h2 className="mt-10 font-display text-3xl leading-tight text-brand-yellow">
									{children}
								</h2>
							),
							h3: ({ children }) => (
								<h3 className="mt-6 font-display text-2xl leading-tight text-brand-white">
									{children}
								</h3>
							),
							h4: ({ children }) => (
								<h4 className="mt-4 font-display text-xl leading-tight text-brand-white">
									{children}
								</h4>
							),
							p: ({ children }) => (
								<p className="mt-4 font-body text-base leading-relaxed text-brand-white/90 sm:text-lg">
									{children}
								</p>
							),
							a: ({ href, children }) => (
								<a
									href={href}
									className="text-brand-yellow underline underline-offset-4 hover:text-brand-white"
								>
									{children}
								</a>
							),
							ul: ({ children }) => (
								<ul className="mt-4 list-disc space-y-2 pl-6 font-body text-base leading-relaxed text-brand-white/90 sm:text-lg">
									{children}
								</ul>
							),
							ol: ({ children }) => (
								<ol className="mt-4 list-decimal space-y-2 pl-6 font-body text-base leading-relaxed text-brand-white/90 sm:text-lg">
									{children}
								</ol>
							),
							li: ({ children }) => <li>{children}</li>,
							strong: ({ children }) => (
								<strong className="font-bold text-brand-white">
									{children}
								</strong>
							),
							em: ({ children }) => (
								<em className="italic text-brand-white">{children}</em>
							),
							code: ({ children }) => (
								<code className="rounded bg-brand-white/10 px-1.5 py-0.5 font-mono text-sm text-brand-yellow">
									{children}
								</code>
							),
							pre: ({ children }) => (
								<pre className="mt-4 overflow-x-auto rounded bg-brand-white/10 p-4 font-mono text-sm text-brand-white/90">
									{children}
								</pre>
							),
							blockquote: ({ children }) => (
								<blockquote className="mt-4 border-l-4 border-brand-yellow pl-4 font-body text-base italic text-brand-white/85">
									{children}
								</blockquote>
							),
							hr: () => <hr className="my-8 border-brand-white/20" />,
						}}
					>
						{markdown}
					</ReactMarkdown>
				) : null}
				{children}
			</div>
		</article>
	);
}
