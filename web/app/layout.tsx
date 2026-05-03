import type { Metadata } from "next";
import { Atkinson_Hyperlegible, VT323 } from "next/font/google";
import "./globals.css";

const display = VT323({
	weight: "400",
	subsets: ["latin"],
	variable: "--font-display",
	display: "swap",
});

const body = Atkinson_Hyperlegible({
	weight: ["400", "700"],
	subsets: ["latin"],
	variable: "--font-body",
	display: "swap",
});

export const metadata: Metadata = {
	title: "Vacation Station 14",
	description:
		"A casual SS14 hangout server. Light roleplay, creativity over violence, chosen-family vibe.",
};

export default function RootLayout({
	children,
}: Readonly<{
	children: React.ReactNode;
}>) {
	return (
		<html
			lang="en"
			className={`${display.variable} ${body.variable} h-full antialiased`}
		>
			<body className="min-h-full flex flex-col font-body bg-brand-blue text-brand-white">
				{children}
			</body>
		</html>
	);
}
