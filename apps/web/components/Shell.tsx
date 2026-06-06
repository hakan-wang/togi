/* ============================================================
   Togi — variant B shell (ported) + the live vertical-slice orchestration.
   Floating sidebar (Today / Sessions / Insights / Settings) + content + dock.
   The check-in pipeline (transcribe → categorize → persist → Real → insight)
   lives in handleCheckin().
   ============================================================ */
"use client";
import * as React from "react";
import { useEffect, useRef, useState } from "react";
import {
  CATEGORIES, COACH_ACK, DAY_START, JUST_ENDED, NOW, REAL_SEED, RealEntry,
} from "../lib/data";
import { transcribeAudio, categorizeText } from "../lib/capture";
import { computeInsight, BannerInsight } from "../lib/insights";
import { loadRealEntries, saveRealEntry, toRealEntry } from "../lib/store";
import { IcChevron, IcInsights, IcMic, IcSettings, IcToday } from "./icons";
import { TodayCheckin, InsightBanner } from "./Today";
import { DayCalendar } from "./Calendar";
import { TogiDock } from "./Dock";
import { SessionsView } from "./Sessions";
import { SessionOverlay } from "./SessionOverlay";
import { InsightsPage, SettingsPage } from "./Pages";

const NAV_B = [
  { id: "today", label: "Today", Icon: IcToday, hint: "Calendar" },
  { id: "sessions", label: "Sessions", Icon: IcMic, hint: "Talk to Togi" },
  { id: "insights", label: "Insights", Icon: IcInsights, hint: "Your data bank" },
  { id: "settings", label: "Settings", Icon: IcSettings, hint: "Preferences" },
];

function SidebarB({ tab, setTab, collapsed, setCollapsed, onTalk }: any) {
  return (
    <nav className={"sidebar-b" + (collapsed ? " collapsed" : "")}>
      <div className="sb-brand">
        <button className="sb-mascot-btn" onClick={onTalk} title="Talk to Togi">
          <img className="sb-mascot bg-bob" src="/togi-mascot.png" alt="Togi" />
        </button>
        {!collapsed && (
          <div className="sb-brand-txt"><div className="sb-word serif">togi</div><div className="sb-tag">to sharpen</div></div>
        )}
      </div>
      <div className="sb-nav">
        {NAV_B.map((n) => (
          <button key={n.id} className={"sb-item" + (tab === n.id ? " active" : "")} onClick={() => setTab(n.id)} title={collapsed ? n.label : ""}>
            <span className="sb-ic"><n.Icon size={19} /></span>
            {!collapsed && <span className="sb-label">{n.label}</span>}
            {!collapsed && tab === n.id && <span className="sb-dot" />}
          </button>
        ))}
      </div>
      <div className="sb-foot">
        <button className="sb-user" title="Håkan Wang">
          <span className="avatar">H</span>
          {!collapsed && <div className="sb-user-txt"><div className="rail-user-name">Håkan Wang</div><div className="rail-user-sub">Private</div></div>}
        </button>
        <button className="sb-collapse" onClick={() => setCollapsed((v: boolean) => !v)} title={collapsed ? "Expand" : "Collapse"}>
          <IcChevron size={16} style={{ transform: collapsed ? "none" : "rotate(180deg)" }} />
        </button>
      </div>
    </nav>
  );
}

const ACCENT = "#2f6bf6";

export function TogiAppB() {
  const [tab, setTab] = useState("today");
  const [view, setView] = useState("real");        // open on the Plan-vs-Real gap
  const [session, setSession] = useState<any>(null);
  const [collapsed, setCollapsed] = useState(false);
  const [coach, setCoach] = useState<any>({ state: "pending", msg: null });
  const [banner, setBanner] = useState(true);
  const [real, setReal] = useState<RealEntry[]>(REAL_SEED);
  const [insight, setInsight] = useState<BannerInsight>(() => computeInsight(REAL_SEED));
  const ackTimer = useRef<any>(null);

  useEffect(() => { document.documentElement.style.setProperty("--togi-live", ACCENT); }, []);

  // Load any previously-persisted live entries so a refresh keeps them.
  useEffect(() => {
    (async () => {
      try {
        const rows = await loadRealEntries();
        if (rows.length) {
          const live = rows.map((r, i) => placeLive(toRealEntry(r, i), r.duration_min || undefined));
          setReal((cur) => {
            const seedIds = new Set(cur.map((x) => x.id));
            const merged = [...cur, ...live.filter((x) => !seedIds.has(x.id))];
            setInsight(computeInsight(merged));
            return merged;
          });
        }
      } catch { /* ignore */ }
    })();
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") { e.preventDefault(); setSession({ mode: "ask" }); }
      if (e.key === "Escape") setSession(null);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);
  useEffect(() => () => clearTimeout(ackTimer.current), []);

  const openSession = (mode: string, ctx?: any) => setSession({ mode, ctx });

  const logged = (msg?: string) => {
    clearTimeout(ackTimer.current);
    setCoach({ state: "ack", msg: msg || COACH_ACK });
    ackTimer.current = setTimeout(() => setCoach({ state: "idle" }), 4800);
  };

  // give an off-plan live entry a start/end window so it renders on the timeline
  function placeLive(entry: RealEntry, durationMin?: number): RealEntry {
    if (entry.slot) return entry; // aligned over a plan block
    const dur = durationMin || 45;
    return { ...entry, off: true, end: NOW, start: Math.max(DAY_START, NOW - dur) };
  }

  // ---- THE VERTICAL SLICE ----
  async function handleCheckin({ blob, text }: { blob?: Blob | null; text?: string }) {
    let transcript = (text || "").trim();
    if (!transcript && blob) transcript = await transcribeAudio(blob);
    if (!transcript) throw new Error("Didn’t catch that — try again, or type instead.");

    const result = await categorizeText(transcript, {
      block: JUST_ENDED.block, planId: JUST_ENDED.planId, window: JUST_ENDED.window, kind: "checkin",
    });

    const entry = placeLive({
      id: `live-${Date.now()}`,
      slot: result.matchedPlanId || undefined,
      off: !result.matchedPlanId,
      match: result.matched,
      cat: result.category,
      sub: result.subCategory,
      title: result.description,
      desc: transcript,
      live: true,
    }, result.durationMin ?? undefined);

    // 1) land it on the Real timeline immediately
    const next = [...real, entry];
    setReal(next);
    setTab("today");
    setView("real");
    // 2) the insight updates
    setInsight(computeInsight(next));
    // 3) persist (Supabase if signed in, else local) — don't block the UI feel
    await saveRealEntry({
      id: entry.id,
      category: result.category,
      sub_category: result.subCategory,
      description: result.description,
      duration_min: result.durationMin,
      matched_plan_id: result.matchedPlanId,
      matched: result.matched,
      transcript,
      started_at: null,
    });
    // 4) coach acknowledges (this also hides the pending check-in card)
    logged(`Logged: ${CATEGORIES[result.category].label} › ${result.subCategory}.`);
  }

  const onAction = (action: string) => {
    if (action === "real") { setTab("today"); setView("real"); logged(COACH_ACK); }
    if (action === "plan") { setTab("today"); setView("plan"); logged("Tomorrow’s taking shape — saved."); }
    setSession(null);
  };

  const dockVisible = tab !== "settings";

  return (
    <div className="shell-b">
      <SidebarB tab={tab} setTab={setTab} collapsed={collapsed} setCollapsed={setCollapsed} onTalk={() => openSession("ask")} />

      <main className="content-b">
        {tab === "today" && (
          <div className="content-today">
            {coach.state === "pending" && <TodayCheckin onSubmit={handleCheckin} />}
            {banner && (
              <InsightBanner data={insight} onApply={() => { setTab("today"); openSession("plan"); }} onDismiss={() => setBanner(false)} />
            )}
            <div className="content-cal">
              <DayCalendar view={view} setView={setView} real={real} density="regular"
                onPlanDay={(d: any) => openSession("plan", d && d.d)}
                onSelfCheckin={(label: string) => openSession("self", label)}
                onTalkBlock={(b: any) => openSession("checkin", b && b.title)} />
            </div>
          </div>
        )}
        {tab === "sessions" && (<div className="content-scroll"><SessionsView onOpenSession={openSession} /></div>)}
        {tab === "insights" && (
          <div className="content-scroll">
            <div className="surface-inner">
              <header className="page-head"><div><div className="eyebrow">What Togi sees</div><h1>Insights</h1></div></header>
              <InsightsPage onOpenSession={openSession} />
            </div>
          </div>
        )}
        {tab === "settings" && (
          <div className="content-scroll">
            <div className="surface-inner">
              <header className="page-head"><div><div className="eyebrow">Preferences</div><h1>Settings</h1></div></header>
              <SettingsPage />
            </div>
          </div>
        )}
      </main>

      {dockVisible && <TogiDock onOpenSession={openSession} coach={coach} />}
      {session && <SessionOverlay mode={session.mode} ctx={session.ctx} onClose={() => setSession(null)} onAction={onAction} />}
    </div>
  );
}
