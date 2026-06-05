import { AppShell } from "@/components/app-shell";
import { BlockCard } from "@/components/block-card";
import { CalendarPlanner } from "@/components/calendar-planner";
import { CoachPanel } from "@/components/coach-panel";
import { SummaryPanels } from "@/components/summary-panels";
import { VoiceCommand } from "@/components/voice-command";

export default function DashboardPage() {
  return (
    <AppShell>
      <div className="max-w-6xl">
        <h1 className="text-3xl font-semibold">Today</h1>
        <p className="mt-2 text-sm text-steel">Intention vs reality for the day.</p>
        <div className="mt-6"><SummaryPanels /></div>
        <div className="mt-6 grid gap-4 lg:grid-cols-[1.2fr_0.8fr]">
          <CalendarPlanner />
          <VoiceCommand />
        </div>
        <section className="mt-6 grid gap-3 lg:grid-cols-2">
          <BlockCard title="Edit video" time="13:00-14:00" intention="Rough cut first 3 minutes" status="planned" />
          <BlockCard title="Email manufacturers" time="15:00-16:00" intention="Send 3 supplier emails" status="logged" />
        </section>
        <div className="mt-6"><CoachPanel /></div>
      </div>
    </AppShell>
  );
}
