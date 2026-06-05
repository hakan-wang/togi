import Link from "next/link";
import { CalendarDays, CreditCard, ClipboardCheck, LineChart, Monitor, Settings } from "lucide-react";

const nav = [
  { href: "/dashboard", label: "Dashboard", icon: CalendarDays },
  { href: "/lock-in", label: "Lock-in", icon: Monitor },
  { href: "/logs", label: "Logs", icon: ClipboardCheck },
  { href: "/patterns", label: "Patterns", icon: LineChart },
  { href: "/settings", label: "Settings", icon: Settings },
  { href: "/billing", label: "Billing", icon: CreditCard }
];

export function AppShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-paper text-ink">
      <aside className="fixed inset-y-0 left-0 hidden w-56 border-r border-line bg-white/70 px-4 py-5 md:block">
        <Link href="/dashboard" className="text-lg font-semibold">Bogi</Link>
        <nav className="mt-8 space-y-1">
          {nav.map((item) => {
            const Icon = item.icon;
            return (
              <Link key={item.href} href={item.href} className="flex items-center gap-2 rounded-md px-3 py-2 text-sm hover:bg-paper">
                <Icon aria-hidden className="h-4 w-4" />
                {item.label}
              </Link>
            );
          })}
        </nav>
      </aside>
      <main className="min-h-screen px-4 py-5 md:ml-56 md:px-8">{children}</main>
    </div>
  );
}
