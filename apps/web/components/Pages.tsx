/* ============================================================
   Togi — Insights & Settings tabs (ported).
   Insights leads with short-term weekly patterns; long-term data bank below.
   (Charts are mock data — explicitly allowed to be faked.)
   ============================================================ */
"use client";
import * as React from "react";
import { useState } from "react";
import { CATEGORIES, DOMAINS, SHORT_TERM_INSIGHTS } from "../lib/data";
import { IcArrow, IcCheck, IcMic, IcSpark } from "./icons";

export function InsightsPage({ onOpenSession }: any) {
  const [range, setRange] = useState("Week");
  const [filter, setFilter] = useState("All");
  const [applied, setApplied] = useState<Record<string, boolean>>({});
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
        <span className="pattern-eyebrow"><IcSpark size={13} /> This week, Togi noticed</span>
        <span className="pattern-sub">Patterns you can’t see from the inside.</span>
      </div>
      <div className="pattern-grid">
        {SHORT_TERM_INSIGHTS.map((p) => {
          const C = DOMAINS[p.domain];
          const isOn = applied[p.id];
          return (
            <div className="pattern-card" key={p.id} style={{ ["--c" as any]: C.color }}>
              <div className="pattern-metric"><span className="pattern-dot" style={{ background: C.color }} />{p.metric}</div>
              <p className="pattern-text">{p.text}</p>
              <button className={"pattern-apply" + (isOn ? " on" : "")} onClick={() => { setApplied((a) => ({ ...a, [p.id]: true })); onOpenSession("plan"); }}>
                {isOn ? <><IcCheck size={14} /> Applied</> : <>Apply to planning <IcArrow size={14} /></>}
              </button>
            </div>
          );
        })}
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

export function SettingsPage() {
  const [s, setS] = useState<any>({ checkin: true, call: false, blank: false, wake: true, reduce: false });
  const set = (k: string) => setS((p: any) => ({ ...p, [k]: !p[k] }));
  const Row = ({ k, title, sub }: any) => (
    <div className="set-row"><div><div className="set-title">{title}</div><div className="set-sub">{sub}</div></div><Toggle on={s[k]} onClick={() => set(k)} /></div>
  );
  return (
    <div className="page-narrow fade-up">
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
