import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Togi",
  description: "Plan with intention. Reflect on reality. Togi is your honest planning coach."
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
