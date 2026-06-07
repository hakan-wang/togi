/* ============================================================
   Togi — variant B shell + live capture orchestration.
   handleCapture(ctx, input) runs the pipeline for ANY entry point:
   transcribe → categorize (with vocab) → clarify? → persist → Real → insight → grow vocab.
   ============================================================ */
"use client";
import * as React from "react";
import { useEffect, useRef, useState } from "react";
import { DOMAINS, DAY_START, DAY_END, Domain, JUST_ENDED, PLAN, PlanBlock, REAL_SEED, RealEntry, STARTER_ACTIVITIES, fmt } from "../lib/data";
import { dayKey, nowMinutes, onDay } from "../lib/dates";
import { loadFacts } from "../lib/userFacts";
import { transcribeAudio, categorizeText } from "../lib/capture";
import { computeInsight, BannerInsight } from "../lib/insights";
import { parseTimeRange, parseDuration, guessPlanMeta, cleanTitle } from "../lib/planparse";
import { advisePlan } from "../lib/planAdvisor";
import { loadMemory, refreshInsights, surfaced } from "../lib/insightMemory";
import { computeStats, seedHistory } from "../lib/behavior";
import { addActivity, addProject, loadPlanLocal, loadRealEntries, loadVocabulary, savePlanLocal, saveRealEntry, toRealEntry, Vocabulary } from "../lib/store";
import { IcChevron, IcInsights, IcMic, IcSettings, IcToday } from "./icons";
import { TodayCheckin, InsightBanner, CapContext, CheckinInput, CheckinResult } from "./Today";
import { DayCalendar } from "./Calendar";
import { TogiDock } from "./Dock";
import { SessionsView } from "./Sessions";
import { SessionOverlay } from "./SessionOverlay";
import { InsightsPage, SettingsPage } from "./Pages";
import { GcalEventEditor, EventDraft } from "./GcalEventEditor";
import * as gcal from "../lib/gcal";

const NAV_B = [
  { id: "today", label: "Today", Icon: IcToday },
  { id: "sessions", label: "Sessions", Icon: IcMic },
  { id: "insights", label: "Insights", Icon: IcInsights },
  { id: "settings", label: "Settings", Icon: IcSettings },
];

function SidebarB({ tab, setTab, collapsed, setCollapsed, onTalk }: any) {
  return (
    <nav className={"sidebar-b" + (collapsed ? " collapsed" : "")}>
      <div className="sb-brand">
        <button className="sb-mascot-btn" onClick={onTalk} title="Talk to Togi"><img className="sb-mascot bg-bob" src="/togi-mascot.png" alt="Togi" /></button>
        {!collapsed && <div className="sb-brand-txt"><div className="sb-word serif">togi</div><div className="sb-tag">to sharpen</div></div>}
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
        <button className="sb-user" title="Håkan Wang"><span className="avatar">H</span>{!collapsed && <div className="sb-user-txt"><div className="rail-user-name">Håkan Wang</div><div className="rail-user-sub">Private</div></div>}</button>
        <button className="sb-collapse" onClick={() => setCollapsed((v: boolean) => !v)} title={collapsed ? "Expand" : "Collapse"}><IcChevron size={16} style={{ transform: collapsed ? "none" : "rotate(180deg)" }} /></button>
      </div>
    </nav>
  );
}

const ACCENT = "#2f6bf6";
const PINNED_CTX: CapContext = { title: JUST_ENDED.block, domain: JUST_ENDED.domain, window: JUST_ENDED.window, planId: JUST_ENDED.planId, mins: JUST_ENDED.mins, kind: "checkin", prompt: `${JUST_ENDED.block} just ended — tell me what really happened.` };

// build a capture context for the various entry points
function blockCtx(b: any): CapContext {
  const planId = b.slot || b.id;
  const win = b.start != null && b.end != null ? `${fmt(b.start)}–${fmt(b.end)}` : undefined;
  return { title: b.title, domain: b.domain as Domain, planId, window: win, kind: "checkin", prompt: `Tell Togi what you did — what really happened with “${b.title}”?` };
}
function blockCtxByName(name: string): CapContext {
  const p = PLAN.find((x) => x.title === name);
  if (p) return blockCtx({ ...p, slot: p.id });
  return { title: name, domain: "Work", kind: "checkin", prompt: `Tell Togi what you did — “${name}”?` };
}
function selfCtx(label: string): CapContext {
  return { title: "Untracked time", domain: "Leisure", window: label, kind: "self", prompt: `Tell Togi what you did ${label}.` };
}
// Plan vs check-in for a tapped block/gap depends on the toggle + whether it's in the past.
function planAtCtx(b?: any): CapContext {
  const win = b && b.start != null && b.end != null ? `${fmt(b.start)}–${fmt(b.end)}` : undefined;
  return { title: "Plan", domain: "Work", window: win, kind: "plan", prompt: "Plan smarter with Togi — what do you want to get done?" };
}
function planCtx(): CapContext { return planAtCtx(); }

export function TogiAppB() {
  const [tab, setTab] = useState("today");
  const [view, setView] = useState("real");
  const [session, setSession] = useState<any>(null);
  const [capture, setCapture] = useState<{ context: CapContext; plan?: boolean } | null>(null);
  const [collapsed, setCollapsed] = useState(false);
  const [coach, setCoach] = useState<any>({ state: "pending", msg: null });
  const [banner, setBanner] = useState(true);
  const [real, setReal] = useState<RealEntry[]>(REAL_SEED);
  const [plan, setPlan] = useState<PlanBlock[]>(PLAN);
  const [selectedDate, setSelectedDate] = useState<string>(() => dayKey());
  const [nowMin, setNowMin] = useState<number>(() => nowMinutes());
  const [bannerInsight, setBannerInsight] = useState<BannerInsight>({ domain: "Errands & life admin", text: "You underestimate errands and travel by ~90 min a day — that’s why afternoons crack.", metric: "+90 min/day" });
  const [calConfigured, setCalConfigured] = useState(false);
  const [calConnected, setCalConnected] = useState(false);
  const [calEmail, setCalEmail] = useState<string | null>(null);
  const [calStatus, setCalStatus] = useState<string | null>(null);
  const [gcalEditor, setGcalEditor] = useState<{ block: PlanBlock | null } | null>(null);
  const [insight, setInsight] = useState<BannerInsight>(() => computeInsight(REAL_SEED));
  const [vocab, setVocab] = useState<Vocabulary>({ projects: [], activities: STARTER_ACTIVITIES });
  const ackTimer = useRef<any>(null);

  useEffect(() => { document.documentElement.style.setProperty("--togi-live", ACCENT); }, []);

  useEffect(() => {
    (async () => {
      try { setVocab(await loadVocabulary()); } catch { /* keep starter */ }
      try { const pl = loadPlanLocal(); if (pl.length) setPlan((cur) => { const ids = new Set(cur.map((x) => x.id)); return [...cur, ...pl.filter((x) => !ids.has(x.id))]; }); } catch { /* ignore */ }
      try {
        const rows = await loadRealEntries();
        if (rows.length) {
          const live = rows.map((r, i) => placeLive(toRealEntry(r, i), r.duration_min || undefined));
          setReal((cur) => {
            const ids = new Set(cur.map((x) => x.id));
            const merged = [...cur, ...live.filter((x) => !ids.has(x.id))];
            setInsight(computeInsight(merged));
            return merged;
          });
        }
      } catch { /* ignore */ }
    })();
  }, []);

  // Google Calendar: read connection status on load, and handle the OAuth return.
  useEffect(() => {
    (async () => {
      const params = new URLSearchParams(window.location.search);
      const ret = params.get("gcal");
      if (ret) {
        if (ret === "connected") setCalStatus("Connected — loading today’s events…");
        else if (ret === "denied") setCalStatus("Connection cancelled.");
        else setCalStatus("Couldn’t connect — check the setup guide and try again.");
        window.history.replaceState({}, "", window.location.pathname); // clean the URL
      }
      try {
        const s = await gcal.getStatus();
        setCalConfigured(s.configured);
        setCalConnected(s.connected);
        setCalEmail(s.email);
        if (s.connected) await refreshCalendar(ret === "connected");
        else if (ret === "connected") setCalStatus("Connected, but no calendar found yet — try Refresh.");
      } catch { /* leave defaults */ }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") { e.preventDefault(); setSession({ mode: "ask" }); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);
  useEffect(() => () => clearTimeout(ackTimer.current), []);

  // Real-time clock for the "now" line.
  useEffect(() => { const t = setInterval(() => setNowMin(nowMinutes()), 15000); return () => clearInterval(t); }, []);

  // Populate the behavioral memory (so planning can use it) and surface a NON-obvious one in the banner.
  useEffect(() => {
    (async () => {
      try {
        let rows = loadMemory();
        if (!rows.length) rows = await refreshInsights(computeStats(seedHistory()), new Date().toISOString());
        const top = surfaced(rows)[0];
        if (top) setBannerInsight({ domain: "Work", text: top.statement, metric: top.metric });
      } catch { /* ignore */ }
    })();
  }, []);

  const openSession = (mode: string, ctx?: any) => setSession({ mode, ctx });
  // route check-in/self entry points to the REAL capture card; ask/plan stay scripted
  const startSession = (mode: string, arg?: any) => {
    if (mode === "self") setCapture({ context: selfCtx(typeof arg === "string" ? arg : "then") });
    else if (mode === "checkin") setCapture({ context: blockCtxByName(typeof arg === "string" ? arg : JUST_ENDED.block) });
    else if (mode === "plan") setCapture({ context: planCtx(), plan: true });
    else openSession(mode, arg);
  };

  const logged = (msg?: string) => { clearTimeout(ackTimer.current); setCoach({ state: "ack", msg }); ackTimer.current = setTimeout(() => setCoach({ state: "idle" }), 4800); };

  function placeLive(entry: RealEntry, durationMin?: number): RealEntry {
    if (entry.slot) return entry;
    const dur = durationMin || 45;
    const n = nowMinutes();
    return { ...entry, off: true, end: n, start: Math.max(DAY_START, n - dur) };
  }

  // ---- THE PIPELINE (any entry point) ----
  async function handleCapture(ctx: CapContext, input: CheckinInput): Promise<CheckinResult> {
    let base = (input.text || "").trim();
    if (!base && input.blob) base = await transcribeAudio(input.blob);
    if (!base) throw new Error("Didn’t catch that — try again, or type instead.");
    const isAnswer = !!input.draftText;
    const utterance = isAnswer ? `${input.draftText}. ${base}`.trim() : base;

    const r = await categorizeText(utterance, { block: ctx.title, planId: ctx.planId, window: ctx.window, kind: ctx.kind }, vocab);
    if (!isAnswer && r.confidence < 0.6 && r.clarify_question) return { status: "clarify", question: r.clarify_question, draftText: utterance };

    const matchedPlanId = r.matched && ctx.planId ? ctx.planId : null;
    const entry = placeLive({
      id: `live-${Date.now()}`, slot: matchedPlanId || undefined, off: !matchedPlanId, match: r.matched,
      domain: r.domain, project: r.project, activity: r.activity, title: r.title, note: r.note, confidence: r.confidence, live: true,
      date: selectedDate,
    }, r.durationMin ?? undefined);

    const next = [...real, entry];
    setReal(next); setTab("today"); setView("real"); setInsight(computeInsight(next));

    if (r.activity && !vocab.activities.some((a) => a.toLowerCase() === r.activity.toLowerCase())) { addActivity(r.activity); setVocab((v) => ({ ...v, activities: [...v.activities, r.activity] })); }
    if (r.project && !vocab.projects.some((p) => p.toLowerCase() === r.project!.toLowerCase())) { addProject(r.project); setVocab((v) => ({ ...v, projects: [...v.projects, r.project!] })); }

    await saveRealEntry({ title: r.title, domain: r.domain, project: r.project, activity: r.activity, note: r.note, duration_min: r.durationMin, matched_plan_id: matchedPlanId, matched: r.matched, confidence: r.confidence, transcript: utterance, started_at: null });
    logged(`Logged: ${DOMAINS[r.domain].label}${r.project ? " › " + r.project : ""} › ${r.activity}`);
    return { status: "done" };
  }

  // ---- PLANNING (adds a categorized block to the Plan timeline) ----
  async function handlePlan(ctx: CapContext, input: CheckinInput): Promise<CheckinResult> {
    let base = (input.text || "").trim();
    if (!base && input.blob) base = await transcribeAudio(input.blob);
    if (!base) throw new Error("Didn’t catch that — try again, or type instead.");
    const isAnswer = !!input.draftText;
    const utterance = isAnswer ? `${input.draftText}. ${base}`.trim() : base;

    // Plans are NOT force-categorized (only real check-ins are): just need a title + time.
    const tr = parseTimeRange(utterance, parseDuration(utterance));
    if (!isAnswer && !tr) return { status: "clarify", question: "When, and for how long?", draftText: utterance };

    const facts = loadFacts();
    const range = tr || { start: facts.wakeMin + 120, end: facts.wakeMin + 120 + (parseDuration(utterance) || 60) };
    const g = guessPlanMeta(utterance);
    let block: PlanBlock = { id: `plan-${Date.now()}`, date: selectedDate, domain: g.domain, project: null, activity: g.activity, title: cleanTitle(isAnswer ? input.draftText! : base), start: range.start, end: range.end };
    // Close the loop: Togi consults the behavioral memory, may move/pad the block, explains why.
    const adv = advisePlan(block, surfaced(loadMemory()));
    block = adv.block;
    // Respect the user's facts: never schedule before their usual wake time.
    let wakeNote = "";
    if (block.start < facts.wakeMin) { const d = block.end - block.start; block = { ...block, start: facts.wakeMin, end: Math.min(DAY_END, facts.wakeMin + d) }; wakeNote = `kept it after your usual ${fmt(facts.wakeMin)} start`; }
    const reasonAll = [adv.reason, wakeNote].filter(Boolean).join(", and ");
    if (reasonAll) block.note = `Togi: ${reasonAll}`;
    const nextPlan = [...plan, block];
    setPlan(nextPlan); setTab("today"); setView("plan");
    savePlanLocal(nextPlan.filter((b) => b.id.startsWith("plan-")));
    logged(`Planned: ${block.title} · ${fmt(block.start)}–${fmt(block.end)}${reasonAll ? " — " + reasonAll : ""}`);
    return { status: "done" };
  }

  // ---- Google Calendar: connect / refresh / disconnect (server-side OAuth) ----
  // Merge Google events into the Plan, replacing any previous Google blocks but
  // keeping the user's own planned/demo blocks.
  function mergeGcal(evs: PlanBlock[]) {
    setPlan((cur) => [...cur.filter((b) => b.source !== "gcal"), ...evs]);
  }

  async function connectCalendar() {
    if (!calConnected) {
      setCalStatus("Opening Google sign-in…");
      try { await gcal.startConnect(); }              // redirects away to Google
      catch (e: any) { setCalStatus(e?.message || "Couldn’t start Google sign-in."); }
      return;
    }
    await refreshCalendar(true); // already connected → Refresh re-pulls today's events
  }

  async function refreshCalendar(announce = false) {
    if (announce) setCalStatus("Refreshing…");
    try {
      const evs = await gcal.fetchTodayEvents();
      setCalConnected(true);
      mergeGcal(evs);
      if (announce) {
        setTab("today"); setView("plan");
        setCalStatus(evs.length ? `Connected — ${evs.length} event${evs.length > 1 ? "s" : ""} today.` : "Connected — no timed events today.");
      }
    } catch (e: any) {
      if (e instanceof gcal.CalendarDisconnected) {
        setCalConnected(false); setCalEmail(null); setPlan((cur) => cur.filter((b) => b.source !== "gcal"));
        setCalStatus("Disconnected — reconnect to sync again.");
      } else setCalStatus(e?.message || "Couldn’t load calendar events.");
    }
  }

  async function disconnectCalendar() {
    setCalStatus("Disconnecting…");
    try { await gcal.disconnect(); } catch { /* best effort */ }
    setCalConnected(false); setCalEmail(null);
    setPlan((cur) => cur.filter((b) => b.source !== "gcal"));
    setCalStatus("Disconnected.");
  }

  // ---- Edit Google Calendar from inside Togi (write-back) ----
  async function saveGcalEvent(draft: EventDraft, gcalId?: string) {
    if (gcalId) await gcal.updateEvent(gcalId, draft);
    else await gcal.createEvent(draft);
    await refreshCalendar(false);
    logged(gcalId ? "Updated in Google Calendar." : "Added to Google Calendar.");
  }
  async function deleteGcalEvent(gcalId: string) {
    await gcal.deleteEvent(gcalId);
    await refreshCalendar(false);
    logged("Deleted from Google Calendar.");
  }

  const onAction = (action: string) => {
    if (action === "real") { setTab("today"); setView("real"); logged("On your Real timeline."); }
    if (action === "plan") { setTab("today"); setView("plan"); logged("Tomorrow’s taking shape — saved."); }
    setSession(null);
  };

  const dockVisible = tab !== "settings";
  const today = dayKey();
  const isToday = selectedDate === today;
  const planForDay = plan.filter((b) => onDay(b, selectedDate, today));
  const realForDay = real.filter((b) => onDay(b, selectedDate, today));

  // Real-time check-in: the most-recently-ended plan block TODAY, not yet logged.
  // (A 2-min check-in falls out the end of every block — nothing shows until one ends.)
  const doneSlots = new Set(real.filter((r) => r.live && r.slot).map((r) => r.slot));
  const dueBlock = plan
    .filter((b) => onDay(b, today, today) && b.end <= nowMin && !doneSlots.has(b.id))
    .sort((a, b) => b.end - a.end)[0];
  const dueCtx: CapContext | null = dueBlock
    ? { title: dueBlock.title, domain: dueBlock.domain, window: `${fmt(dueBlock.start)}–${fmt(dueBlock.end)}`, planId: dueBlock.id, mins: 2, kind: "checkin", prompt: `“${dueBlock.title}” just ended — tell Togi what really happened.` }
    : null;

  return (
    <div className="shell-b">
      <SidebarB tab={tab} setTab={setTab} collapsed={collapsed} setCollapsed={setCollapsed} onTalk={() => openSession("ask")} />
      <main className="content-b">
        {tab === "today" && (
          <div className="content-today">
            {isToday && dueCtx && <TodayCheckin context={dueCtx} onSubmit={(input) => handleCapture(dueCtx, input)} />}
            {banner && <InsightBanner data={bannerInsight} onApply={() => setCapture({ context: planCtx(), plan: true })} onDismiss={() => setBanner(false)} />}
            <div className="content-cal">
              <DayCalendar view={view} setView={setView} real={realForDay} plan={planForDay} now={nowMin} selectedDate={selectedDate} density="regular"
                onSelectDay={(key: string) => setSelectedDate(key)}
                onPlanDay={(key: string) => { setSelectedDate(key); setCapture({ context: planCtx(), plan: true }); }}
                onSelfCheckin={(label: string) => { const wantPlan = view === "plan" || selectedDate > today; setCapture(wantPlan ? { context: planCtx(), plan: true } : { context: selfCtx(label) }); }}
                onTalkBlock={(b: any) => { const future = selectedDate > today || (selectedDate === today && (b.start ?? 0) > nowMin); const wantPlan = view === "plan" || future; setCapture(wantPlan ? { context: planAtCtx(b), plan: true } : { context: blockCtx(b) }); }}
                onEditBlock={calConnected ? (b: PlanBlock) => setGcalEditor({ block: b }) : undefined} />
            </div>
          </div>
        )}
        {tab === "sessions" && (<div className="content-scroll"><SessionsView onOpenSession={startSession} /></div>)}
        {tab === "insights" && (<div className="content-scroll"><div className="surface-inner"><header className="page-head"><div><div className="eyebrow">What Togi sees</div><h1>Insights</h1></div></header><InsightsPage onOpenSession={openSession} /></div></div>)}
        {tab === "settings" && (<div className="content-scroll"><div className="surface-inner"><header className="page-head"><div><div className="eyebrow">Preferences</div><h1>Settings</h1></div></header><SettingsPage onConnectCalendar={connectCalendar} onDisconnectCalendar={disconnectCalendar} onAddEvent={() => setGcalEditor({ block: null })} calStatus={calStatus} calConnected={calConnected} calConfigured={calConfigured} calEmail={calEmail} /></div></div>)}
      </main>
      {dockVisible && <TogiDock onOpenSession={startSession} coach={coach} />}
      {capture && <TodayCheckin context={capture.context} onSubmit={(input) => capture.plan ? handlePlan(capture.context, input) : handleCapture(capture.context, input)} onClose={() => setCapture(null)} />}
      {session && <SessionOverlay mode={session.mode} ctx={session.ctx} onClose={() => setSession(null)} onAction={onAction} />}
      {gcalEditor && <GcalEventEditor block={gcalEditor.block} onSave={saveGcalEvent} onDelete={deleteGcalEvent} onClose={() => setGcalEditor(null)} />}
    </div>
  );
}
