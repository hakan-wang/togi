/* ============================================================
   Togi — Sessions. Every planned block gets a 2-min check-in, tied to the real
   calendar: due now (ended, not logged) → scheduled (later today) → earlier (done).
   Plus a Talk-to-Togi card, the daily planning ritual, and "planned but not done".
   ============================================================ */
"use client";
import * as React from "react";
import { useState } from "react";
import { DOMAINS, domainShort, DISCREPANCIES, PlanBlock, RealEntry, fmt } from "../lib/data";
import { IcArrow, IcCheck, IcMic, IcPlan, IcReturn, IcTrash, IcWave } from "./icons";

function CheckinRow({ block, status, onSession }: { block: PlanBlock; status: "due" | "scheduled" | "done"; onSession: any }) {
  const C = DOMAINS[block.domain];
  if (status === "done") {
    return (
      <div className="ses-row done">
        <span className="ses-tick"><IcCheck size={14} /></span>
        <div className="ses-main"><div className="ses-title">{block.title}</div><div className="ses-sub">logged · {domainShort(block.domain)}</div></div>
        <span className="ses-at num">{fmt(block.end)}</span>
      </div>
    );
  }
  return (
    <button className={"ses-row" + (status === "due" ? " due" : "")} onClick={() => onSession("checkin", block.title)}>
      <span className="ses-ic" style={{ color: C.color }}><IcMic size={16} /></span>
      <div className="ses-main">
        <div className="ses-title-row">
          <span className="ses-title">{block.title}</span>
          <span className="ses-chip"><span className="cat-swatch" style={{ background: C.color }} />{domainShort(block.domain)}</span>
        </div>
        <div className="ses-sub num">{fmt(block.start)}–{fmt(block.end)}</div>
      </div>
      <div className="ses-right">
        <span className={"ses-when num" + (status === "due" ? " due" : "")}>{status === "due" ? "now" : fmt(block.end)}</span>
        <span className="ses-mins num">2 min</span>
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

export function SessionsView({ onSession, onTalk, plan = [], real = [], today, nowMin = 0, planningMin = 1260 }: any) {
  const todays: PlanBlock[] = plan.filter((b: PlanBlock) => (b.date || today) === today).sort((a: PlanBlock, b: PlanBlock) => a.start - b.start);
  const liveSlots = new Set(real.filter((r: RealEntry) => r.live && r.slot).map((r: RealEntry) => r.slot));
  const ended = todays.filter((b) => b.end <= nowMin);
  const due = ended.filter((b) => !liveSlots.has(b.id));
  const dueNow = due[due.length - 1];                    // most recently ended, not yet checked in
  const earlier = ended.filter((b) => liveSlots.has(b.id) || b !== dueNow); // already-passed blocks
  const upcoming = todays.filter((b) => b.end > nowMin); // later today

  return (
    <div className="ses-view fade-up">
      <header className="ses-head">
        <div className="ses-eyebrow">How Togi learns</div>
        <h1 className="ses-h1">Two minutes, <em className="serif">out loud.</em></h1>
        <p className="ses-lede">Togi doesn’t track you in the background. It asks. A short voice check-in at the end of each block — and your real day fills itself in. <span className="dim">The calendar is just the mirror.</span></p>
      </header>

      {/* Talk to Togi persona */}
      <button className="ses-talk" onClick={onTalk}>
        <span className="ses-talk-orb"><img className="bg-bob" src="/togi-mascot.png" alt="Togi" /></span>
        <div className="ses-talk-txt"><div className="ses-talk-title">Talk to Togi</div><div className="ses-talk-sub">Ask anything, or tell Togi to change a setting — just speak.</div></div>
        <span className="ses-talk-go"><IcMic size={17} /></span>
      </button>

      {/* due-now check-in (light) */}
      {dueNow ? (
        <section className="ses-now-light">
          <div className="ses-now-l">
            <span className="ses-now-badge"><span className="persona-live-dot" /> Waiting on you</span>
            <div className="ses-now-title">{dueNow.title}</div>
            <div className="ses-now-note">That block just ended — let’s log what really happened.</div>
            <div className="ses-now-meta num">{fmt(dueNow.start)}–{fmt(dueNow.end)} · 2 min · voice</div>
          </div>
          <button className="ses-now-cta" onClick={() => onSession("checkin", dueNow.title)}><span className="ses-now-orb"><IcMic size={20} /></span> Start check-in</button>
        </section>
      ) : (
        <div className="ses-allclear"><IcCheck size={16} /> All caught up — your next check-in appears when a block ends.</div>
      )}

      <button className="ses-manual" onClick={() => onSession("self", "right now")}>
        <span className="ses-manual-ic"><IcWave size={18} /></span>
        <div className="ses-manual-txt"><div className="ses-manual-title">Self check-in now</div><div className="ses-manual-sub">Log an untracked stretch whenever you want — no schedule needed.</div></div>
        <IcArrow size={16} className="ses-manual-go" />
      </button>

      {upcoming.length > 0 && (
        <section className="ses-section">
          <div className="ses-section-h"><span className="ses-section-t">Scheduled check-ins</span><span className="ses-section-c">one per block, 2 min each</span></div>
          <div className="ses-list">{upcoming.map((b) => <CheckinRow key={b.id} block={b} status="scheduled" onSession={onSession} />)}</div>
        </section>
      )}

      <section className="ses-section">
        <div className="ses-section-h"><span className="ses-section-t">Daily planning</span><span className="ses-section-c">talk to Togi · {fmt(planningMin)}</span></div>
        <div className="ses-list">
          <button className="ses-row ses-plan-row" onClick={() => onSession("plan")}>
            <span className="ses-ic" style={{ color: "var(--togi-live)" }}><IcPlan size={17} /></span>
            <div className="ses-main"><div className="ses-title">Planning session</div><div className="ses-sub">Shape tomorrow with Togi — it uses your memory to plan smarter.</div></div>
            <div className="ses-right"><span className="ses-when num">{fmt(planningMin)}</span><span className="ses-mins num">5 min</span></div>
            <span className="ses-go"><IcArrow size={16} /></span>
          </button>
        </div>
      </section>

      <section className="ses-section">
        <div className="ses-section-h"><span className="ses-section-t">Planned but not done</span><span className="ses-section-c">reschedule, or let it go</span></div>
        <PlannedNotDone />
      </section>

      {earlier.length > 0 && (
        <section className="ses-section">
          <div className="ses-section-h"><span className="ses-section-t">Earlier today</span><span className="ses-section-c">already logged</span></div>
          <div className="ses-list">{earlier.map((b) => <CheckinRow key={b.id} block={b} status="done" onSession={onSession} />)}</div>
        </section>
      )}
    </div>
  );
}
