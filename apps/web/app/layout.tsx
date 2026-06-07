import type { Metadata, Viewport } from "next";
// Design tokens (order matters — mirrors the _ds styles.css entry point)
import "../styles/tokens/fonts.css";
import "../styles/tokens/colors.css";
import "../styles/tokens/typography.css";
import "../styles/tokens/spacing.css";
import "../styles/tokens/effects.css";
import "../styles/tokens/motion.css";
// App styles (order mirrors Togi B.html)
import "../styles/togi.css";
import "../styles/calendar.css";
import "../styles/companion.css";
import "../styles/session.css";
import "../styles/pages.css";
import "../styles/layout-b.css";

export const metadata: Metadata = {
  title: "Togi — to sharpen",
  description: "A voice-first accountability coach. See the gap between your plan and your real day.",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        {children}
      </body>
    </html>
  );
}
