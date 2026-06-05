import "./globals.css";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Bogi",
  description: "Calendar intention, screen accountability, and reality logs."
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
