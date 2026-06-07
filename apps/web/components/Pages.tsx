/* ============================================================
   Togi — Insights & Settings tabs (ported).
   Insights leads with short-term weekly patterns; long-term data bank below.
   (Charts are mock data — explicitly allowed to be faked.)
   ============================================================ */
"use client";
import * as React from "react";
import { useEffect, useState } from "react";
import { CATEGORIES, DOMAINS, SHORT_TERM_INSIGHTS } from "../lib/data";
import { IcArrow, IcCheck, IcClose, IcMic, IcSpark, IcPlus } from "./icons";
import { computeStats, seedHistory } from "../lib/behavior";
import { dismiss, InsightRecord, loadMemory, refreshInsights, surfaced } from "../lib/insightMemory";

const FAMILY_COLOR: Record<string, string> = {
  drift: "var(--cat-creative)", estimation: "var(--cat-errands)", distraction: "var(--cat-scroll)",
  rhythm: "var(--cat-deepwork)", follow_through: "var(--cat-deepwork)", second_order: "var(--cat-health)",
};

export function InsightsPage({ onOpenSession }: any) {
  const [range, setRange] = useState("Week");
  const [filter, setFilter] = useState("All");
  const [applied, setApplied] = useState<Record<string, boolean>>({});
  const [insights, setInsights] = useState<InsightRecord[]>([]);
  const [loadingI, setLoadingI] = useState(false);

  const runRefresh = async () => {
    setLoadingI(true);
    try {
      const stats = computeStats(seedHistory());
      const rows = await refreshInsights(stats, new Date().toISOString());
      setInsights(surfaced(rows));
    } finally { setLoadingI(false); }
  };
  // show memory immediately, then re-analyze when the tab opens (per the spec cadence)
  useEffect(() => { setInsights(surfaced(loadMemory())); runRefresh(); }, []); // eslint-disable-line
  const ranges = ["Week", "Month", "3 months", "Year"];
  const cats = ["All", "Deep work", "Creative", "Scrolling", "Health", "Friends"];

  const weekly: [string, number][] = [
    ["deepwork", 640], ["creative", 520], ["admin", 210], ["health", 240],
    ["social", 300], ["errands", 150], ["leisure", 380], ["scroll", 220], ["personal", 130],
  ];
  const max = Math.max(...weekly.map((w) => w[1]));

  return (
    <div className="page-wide fade-up">
      <div className="pattern-head">
        <span className="pattern-eyebrow"><IcSpark size={13} /> {loadingI ? "Togi is looking…" : "Togi noticed"}</span>
        <span className="pattern-sub">Patterns you can’t see from the inside.</span>
        <button className="ask-chip" style={{ marginLeft: "auto" }} onClick={runRefresh} disabled={loadingI}>{loadingI ? "Analyzing…" : "Refresh"}</button>
      </div>
      <div className="pattern-grid">
        {(insights.length
          ? insights.map((i) => ({ id: i.id, color: FAMILY_COLOR[i.family] || "var(--cat-deepwork)", metric: i.metric || i.family, statement: i.statement, suggestion: i.suggestion, dismissable: true }))
          : SHORT_TERM_INSIGHTS.map((p) => ({ id: p.id, color: DOMAINS[p.domain].color, metric: p.metric, statement: p.text, suggestion: undefined as string | undefined, dismissable: false }))
        ).map((c) => (
          <div className="pattern-card" key={c.id} style={{ ["--c" as any]: c.color }}>
            <div className="pattern-metric" style={{ display: "flex", alignItems: "center", gap: 7, width: "100%" }}>
              <span className="pattern-dot" style={{ background: c.color }} />{c.metric}
              {c.dismissable && <button className="ib-x" title="Not true — forget this" style={{ marginLeft: "auto" }} onClick={() => setInsights(surfaced(dismiss(c.id)))}><IcClose size={12} /></button>}
            </div>
            <p className="pattern-text">{c.statement}</p>
            <button className="pattern-apply" onClick={() => onOpenSession("plan")}>{c.suggestion || "Apply to planning"} <IcArrow size={14} /></button>
          </div>
        ))}
      </div>

      <div className="bank-section-label">The long view</div>
      <div className="card ask-card">
        <div className="ask-top"><span className="insight-badge"><IcSpark size={14} /></span><span className="ask-label">Ask Togi anything about your time</span></div>
        <button className="ask-box" onClick={() => onOpenSession("ask")}>
          <span className="ask-placeholder">“Show me every time I scrolled this month, and when it peaked”</span>
          <span className="ask-go"><IcMic size={15} /></span>
        </button>
        <div className="ask-suggest">
          {["Where did my time go today?", "Productive hours this month", "When do I scroll most?"].map((q) => (
            <button key={q} className="ask-chip" onClick={() => onOpenSession("ask")}>{q}</button>
          ))}
        </div>
      </div>

      <div className="card">
        <div className="card-head">
          <span className="card-title">The data bank</span>
          <div className="seg-mini">{ranges.map((r) => <button key={r} className={range === r ? "on" : ""} onClick={() => setRange(r)}>{r}</button>)}</div>
        </div>
        <div className="filter-row">{cats.map((c) => <button key={c} className={"filter-chip" + (filter === c ? " on" : "")} onClick={() => setFilter(c)}>{c}</button>)}</div>
        <div className="bank-chart">
          {weekly.map(([cat, m]) => {
            const C = CATEGORIES[cat as keyof typeof CATEGORIES];
            const dim = filter !== "All" && C.label !== filter;
            const h = Math.floor(m / 60), mm = m % 60;
            return (
              <div className={"bank-col" + (dim ? " dim-col" : "")} key={cat} title={C.label}>
                <span className="bank-val num">{h}h{mm ? mm : ""}</span>
                <span className="bank-bar" style={{ height: (m / max * 150 + 10) + "px", background: C.color }} />
                <span className="cat-swatch" style={{ background: C.color }} />
              </div>
            );
          })}
        </div>
        <div className="bank-note"><IcSpark size={13} /> Over {range.toLowerCase()}: <strong>10h 40m</strong> deep work, but <strong>3h 40m</strong> of it shadowed by scrolling during planned blocks.</div>
      </div>
    </div>
  );
}

function Toggle({ on, onClick }: any) {
  return <button className={"toggle" + (on ? " on" : "")} onClick={onClick}><span className="toggle-knob" /></button>;
}

export function SettingsPage({ onConnectCalendar, onDisconnectCalendar, onAddEvent, calStatus, calConnected, calConfigured, calEmail }: { onConnectCalendar?: () => void; onDisconnectCalendar?: () => void; onAddEvent?: () => void; calStatus?: string | null; calConnected?: boolean; calConfigured?: boolean; calEmail?: string | null }) {
  const [s, setS] = useState<any>({ checkin: true, call: false, blank: false, wake: true, reduce: false });
  const set = (k: string) => setS((p: any) => ({ ...p, [k]: !p[k] }));
  const Row = ({ k, title, sub }: any) => (
    <div className="set-row"><div><div className="set-title">{title}</div><div className="set-sub">{sub}</div></div><Toggle on={s[k]} onClick={() => set(k)} /></div>
  );
  const calSub = calConnected
    ? (calEmail ? `Connected as ${calEmail}` : "Google Calendar connected")
    : calConfigured === false
      ? "Not configured yet — add Google credentials on the server (see SETUP_GOOGLE_CALENDAR.md)."
      : "Connect so Togi can read your real events and let you edit them here.";
  return (
    <div className="page-narrow fade-up">
      <div className="card">
        <div className="card-head"><span className="card-title">Calendar</span><span className="card-sub">read &amp; edit your real day</span></div>
        <div className="set-row">
          <div>
            <div className="set-title">{calConnected ? "Google Calendar connected" : "Connect Google Calendar"}</div>
            <div className="set-sub">{calStatus || calSub}</div>
          </div>
          <button className="cta-btn" style={{ flex: "0 0 auto" }} disabled={calConfigured === false} onClick={() => onConnectCalendar && onConnectCalendar()}>
            <IcMic size={15} /> {calConnected ? "Refresh" : "Connect"}
          </button>
        </div>
        {calConnected && (
          <>
            <div className="hairline" />
            <div className="set-row">
              <div><div className="set-title">Edit your calendar</div><div className="set-sub">Add an event, or tap the ✎ on any Google block in the Plan view.</div></div>
              <div style={{ display: "flex", gap: 8, flex: "0 0 auto" }}>
                <button className="btn-ghost" onClick={() => onAddEvent && onAddEvent()}><IcPlus size={14} /> Add event</button>
                <button className="btn-ghost" style={{ color: "var(--danger, #d8443c)" }} onClick={() => onDisconnectCalendar && onDisconnectCalendar()}>Disconnect</button>
              </div>
            </div>
          </>
        )}
      </div>
      <div className="card">
        <div className="card-head"><span className="card-title">Check-ins</span><span className="card-sub">a nudge, never a nag</span></div>
        <Row k="checkin" title="Remind me when a block ends" sub="Default on — you downloaded Togi for this. Toggle off anytime." />
        <div className="hairline" />
        <Row k="call" title="Let Togi call me at check-in time" sub="If you don’t answer, it falls back to a quiet notification." />
        <div className="hairline" />
        <Row k="blank" title="Hourly nudge during blank stretches" sub="For the empty 2–3 hour gaps with nothing planned." />
      </div>
      <div className="card">
        <div className="card-head"><span className="card-title">Voice</span></div>
        <Row k="wake" title="Tap-to-talk (axolotl / ⌘K)" sub="The mic only opens on a tap — never listens on its own." />
        <div className="hairline" />
        <Row k="reduce" title="Reduce motion" sub="Calmer transitions on the calendar flip." />
      </div>
      <div className="card set-account">
        <div className="avatar" style={{ width: 38, height: 38 }}>H</div>
        <div><div className="set-title">Håkan Wang</div><div className="set-sub">Private · your data stays yours</div></div>
        <button className="btn-ghost">Manage</button>
      </div>
    </div>
  );
}
