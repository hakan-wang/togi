/* ============================================================
   Togi — variant B: Sessions, a first-class view (ported).
   Sessions are how all data is collected; the calendar is the mirror.
   ============================================================ */
"use client";
import * as React from "react";
import { useState } from "react";
import { DOMAINS, domainShort, DISCREPANCIES, SESSION_FEED } from "../lib/data";
import { IcArrow, IcCheck, IcMic, IcPlan, IcReturn, IcSpark, IcTrash, IcWave } from "./icons";

function SessionRow({ data, onOpenSession }: any) {
  const C = data.domain ? DOMAINS[data.domain] : null;
  const isPlanning = data.kind === "planning";
  const isMorning = data.kind === "morning";
  const icon = isPlanning ? <IcPlan size={17} /> : isMorning ? <IcSpark size={16} /> : <IcMic size={16} />;
  const label = isPlanning ? "Planning session" : data.block;

  if (data.done || data.logged) {
    return (
      <div className="ses-row done">
        <span className="ses-tick"><IcCheck size={14} /></span>
        <div className="ses-main"><div className="ses-title">{label}</div><div className="ses-sub">{data.logged}</div></div>
        <span className="ses-at num">{data.at}</span>
      </div>
    );
  }
  return (
    <button className={"ses-row" + (data.status === "due" ? " due" : "")} onClick={() => onOpenSession(isPlanning ? "plan" : "checkin", data.block)}>
      <span className="ses-ic" style={C ? { color: C.color } : undefined}>{icon}</span>
      <div className="ses-main">
        <div className="ses-title-row">
          <span className="ses-title">{label}</span>
          {C && <span className="ses-chip"><span className="cat-swatch" style={{ background: C.color }} />{domainShort(data.domain)}</span>}
        </div>
        <div className="ses-sub">{data.note || data.window || ""}</div>
      </div>
      <div className="ses-right">
        <span className={"ses-when num" + (data.status === "due" ? " due" : "")}>{data.status === "due" ? "now" : (data.at || data.rel)}</span>
        <span className="ses-mins num">{data.mins} min</span>
      </div>
      <span className="ses-go"><IcArrow size={16} /></span>
    </button>
  );
}

function PlannedNotDone() {
  const [items, setItems] = useState(DISCREPANCIES);
  const [toast, setToast] = useState<string | null>(null);
  const act = (id: string, kind: string) => {
    const it = items.find((x) => x.id === id)!;
    setItems(items.filter((x) => x.id !== id));
    setToast(kind === "resched" ? `Rescheduled “${it.title}” → tomorrow` : `Dropped “${it.title}”`);
    setTimeout(() => setToast(null), 2600);
  };
  if (items.length === 0) return <div className="pnd-empty"><IcCheck size={16} /> Nothing hanging over you — all caught up.</div>;
  return (
    <div className="pnd-list">
      {items.map((t) => {
        const C = DOMAINS[t.domain];
        return (
          <div className="pnd-row" key={t.id}>
            <span className="cat-swatch" style={{ background: C.color, marginTop: 6 }} />
            <div className="pnd-body"><div className="pnd-title">{t.title}</div><div className="pnd-meta">{t.planned} · {t.last}</div></div>
            <div className="pnd-actions">
              <button className="pnd-btn resched" onClick={() => act(t.id, "resched")}><IcReturn size={13} /> Reschedule</button>
              <button className="pnd-btn drop" onClick={() => act(t.id, "drop")}><IcTrash size={13} /> Drop</button>
            </div>
          </div>
        );
      })}
      {toast && <div className="thread-toast num">{toast}</div>}
    </div>
  );
}

export function SessionsView({ onOpenSession }: any) {
  const F = SESSION_FEED;
  const due = { ...F.due, status: "due" };
  return (
    <div className="ses-view fade-up">
      <header className="ses-head">
        <div className="ses-eyebrow">How Togi learns</div>
        <h1 className="ses-h1">Two minutes, <em className="serif">out loud.</em></h1>
        <p className="ses-lede">Togi doesn’t track you in the background. It asks. A few short voice check-ins a day — and your real time fills itself in. <span className="dim">The calendar is just the mirror.</span></p>
      </header>

      <section className="ses-now">
        <div className="ses-now-glow" />
        <div className="ses-now-l">
          <span className="ses-now-badge"><span className="persona-live-dot" /> Waiting on you</span>
          <div className="ses-now-title">{due.block}</div>
          <div className="ses-now-note">{due.note}</div>
          <div className="ses-now-meta num">{due.window} · {due.mins} min · voice</div>
        </div>
        <button className="ses-now-cta" onClick={() => onOpenSession("checkin", due.block)}>
          <span className="ses-now-orb"><IcMic size={20} /></span> Start check-in
        </button>
      </section>

      <button className="ses-manual" onClick={() => onOpenSession("self", "right now")}>
        <span className="ses-manual-ic"><IcWave size={18} /></span>
        <div className="ses-manual-txt"><div className="ses-manual-title">Self check-in now</div><div className="ses-manual-sub">Log an untracked stretch whenever you want — no schedule needed.</div></div>
        <IcArrow size={16} className="ses-manual-go" />
      </button>

      <section className="ses-section">
        <div className="ses-section-h"><span className="ses-section-t">Scheduled today</span><span className="ses-section-c">tied to your blocks</span></div>
        <div className="ses-list">{F.upcoming.map((s) => <SessionRow key={s.id} data={s} onOpenSession={onOpenSession} />)}</div>
      </section>

      <section className="ses-section">
        <div className="ses-section-h"><span className="ses-section-t">Daily planning</span><span className="ses-section-c">the evening ritual</span></div>
        <div className="ses-list"><SessionRow data={F.planning} onOpenSession={onOpenSession} /></div>
      </section>

      <section className="ses-section">
        <div className="ses-section-h"><span className="ses-section-t">Planned but not done</span><span className="ses-section-c">reschedule, or let it go</span></div>
        <PlannedNotDone />
      </section>

      <section className="ses-section">
        <div className="ses-section-h"><span className="ses-section-t">Collected earlier</span><span className="ses-section-c">already on your calendar</span></div>
        <div className="ses-list">{F.done.map((s) => <SessionRow key={s.id} data={s} onOpenSession={onOpenSession} />)}</div>
      </section>
    </div>
  );
}
