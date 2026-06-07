/* ============================================================
   Togi — DayCalendar. Real dates + real clock. Plan / Real toggle.
   Click a day to view it; the + plans that day with Togi. Now-line tracks the
   real time and only shows on today. Blocks render: title · project chip · note.
   ============================================================ */
"use client";
import * as React from "react";
import { useEffect, useRef, useState } from "react";
import { DOMAINS, DAY_START, DAY_END, PLAN, RealEntry, REAL_SEED, UPCOMING, fmt } from "../lib/data";
import { dayKey, dayLabel, weekDays, WeekDay } from "../lib/dates";
import { IcCheck, IcClose, IcChat, IcExpand, IcMinimize, IcPlus, IcEdit } from "./icons";
import { useRecorder } from "../lib/useRecorder";

function DaySelector({ selectedDate, onSelectDay, onPlanDay }: any) {
  const week = weekDays();
  return (
    <div className="day-strip">
      {week.map((w: WeekDay) => (
        <button key={w.key}
          className={"day-cell" + (w.key === selectedDate ? " sel" : "") + (w.isToday ? " today" : "") + (w.isFuture ? " future" : "")}
          onClick={() => onSelectDay(w.key)} title={w.isToday ? "Today" : w.dow}>
          <span className="day-cell-d">{w.dow}</span><span className="day-cell-n num">{w.n}</span>
          {!w.isPast && (
            <span className="day-cell-plan" title="Plan this day with Togi" onClick={(e) => { e.stopPropagation(); onPlanDay(w.key); }}><IcPlus size={11} /></span>
          )}
        </button>
      ))}
    </div>
  );
}

function BlockEl({ top, height, domain, title, project, note, time, layer, tag, live, onClick, editable, onEdit }: any) {
  const C = DOMAINS[domain];
  const tiny = height < 40;
  return (
    <div className={"blk blk-" + layer + (tag ? " has-tag" : "") + (live ? " blk-live" : "")}
      style={{ top, height: Math.max(height, 22), background: C.tint, ["--c" as any]: C.color }} onClick={onClick}>
      <span className="blk-rail" />
      {editable && (
        <button className="blk-edit" title="Edit in Google Calendar" onClick={onEdit}
          style={{ position: "absolute", top: 4, right: 4, zIndex: 2, display: "grid", placeItems: "center", width: 22, height: 22, borderRadius: 6, border: "none", background: "rgba(255,255,255,0.7)", color: C.color, cursor: "pointer" }}>
          <IcEdit size={12} />
        </button>
      )}
      <div className="blk-body">
        <div className="blk-row">
          <span className="blk-title">{title}</span>
          {project && <span className="blk-proj">{project}</span>}
          {tag === "off" && <span className="blk-leak-tag">off-plan</span>}
          {tag === "match" && <span className="blk-check"><IcCheck size={11} /></span>}
          {tag === "unplanned" && <span className="blk-unplanned">unplanned</span>}
          {live && <span className="blk-unplanned">just logged</span>}
        </div>
        <div className="blk-meta">
          <span className="blk-time num">{time}</span>
          {!tiny && note && <span className="blk-sub">{note}</span>}
        </div>
      </div>
    </div>
  );
}

function realStart(r: RealEntry, plan: any[]): number { const p = r.slot ? plan.find((x) => x.id === r.slot) : null; return p ? p.start : (r.start ?? 12 * 60); }

function MinimizedDay({ view, real, plan, onExpand, onTalkBlock }: any) {
  const list = view === "plan" ? plan : [...real].sort((a: RealEntry, b: RealEntry) => realStart(a, plan) - realStart(b, plan));
  return (
    <div className="mini">
      <div className="mini-list">
        {list.length === 0 && <div className="mini-empty num" style={{ padding: "10px 4px", color: "var(--togi-muted)", fontSize: 12 }}>Nothing here yet — tap + to plan.</div>}
        {list.slice(0, 5).map((b: any) => {
          const C = DOMAINS[b.domain];
          return (
            <button className="mini-row" key={b.id} onClick={() => onTalkBlock(b)}>
              <span className="mini-time num">{fmt(view === "plan" ? b.start : realStart(b, plan))}</span>
              <span className="mini-rail" style={{ background: C.color }} />
              <span className="mini-title">{b.title}</span>
            </button>
          );
        })}
      </div>
      <div className="mini-up">
        <div className="mini-up-h">Coming up</div>
        {UPCOMING.map((u, i) => {
          const C = DOMAINS[u.domain];
          return (
            <div className="mini-up-row" key={i}>
              <span className="cat-swatch" style={{ background: C.color }} />
              <span className="mini-up-t">{u.title}</span>
              <span className="mini-up-at num">{u.at}</span>
            </div>
          );
        })}
      </div>
      <button className="mini-expand" onClick={onExpand}><IcExpand size={14} /> Open full day</button>
    </div>
  );
}

function MultiDay({ span, plan }: { span: string; plan: any[] }) {
  const wk = weekDays();
  const todayIdx = Math.max(0, wk.findIndex((w) => w.isToday));
  const days = span === "3d" ? wk.slice(todayIdx, todayIdx + 3) : wk;
  const ppm = 0.5;
  const H = (DAY_END - DAY_START) * ppm;
  const yOf = (m: number) => (m - DAY_START) * ppm;
  const labels: number[] = [];
  for (let m = DAY_START; m <= DAY_END; m += 120) labels.push(m);
  const dayBlocks = (idx: number, isToday: boolean) => (isToday ? plan : plan.filter((_, k) => (k + idx) % 3 !== 0));
  return (
    <div className="multi" style={{ height: H + 34 }}>
      <div className="multi-gutter" style={{ height: H }}>
        {labels.map((m) => <div key={m} className="multi-hr num" style={{ top: yOf(m) }}>{fmt(m)}</div>)}
      </div>
      {days.map((w: WeekDay, i: number) => (
        <div className="multi-col" key={w.key}>
          <div className={"multi-col-h" + (w.isToday ? " today" : "")}><span className="multi-col-d">{w.dow}</span> <span className="multi-col-n num">{w.n}</span></div>
          <div className="multi-track" style={{ height: H }}>
            {labels.map((m) => <div key={m} className="multi-line" style={{ top: yOf(m) }} />)}
            {dayBlocks(i, w.isToday).map((b) => {
              const C = DOMAINS[b.domain];
              return <div className="multi-blk" key={b.id} title={`${C.label} · ${b.title}`}
                style={{ top: yOf(b.start), height: Math.max((b.end - b.start) * ppm, 11), background: C.color, opacity: w.isToday ? 1 : 0.8 }} />;
            })}
          </div>
        </div>
      ))}
    </div>
  );
}

export function DayCalendar({ view, setView, real = REAL_SEED, plan = PLAN, now = 0, selectedDate, onSelectDay, onPlanDay, buildCtx, onVoice, onType, onEditBlock, density }: any) {
  const [expanded, setExpanded] = useState(true);
  const [span, setSpan] = useState("1d");
  const [listen, setListen] = useState<any>(null);  // { x, y, ctx, label, busy }
  const [drag, setDrag] = useState<any>(null);
  const trackRef = useRef<HTMLDivElement>(null);
  const rec = useRecorder();

  const isToday = selectedDate === dayKey();
  const ppm = density === "compact" ? 0.62 : density === "comfy" ? 0.82 : 0.72;
  const trackH = (DAY_END - DAY_START) * ppm;
  const yOf = (m: number) => (m - DAY_START) * ppm;
  const mOf = (y: number) => Math.round((y / ppm + DAY_START) / 5) * 5;

  const hours: number[] = [];
  for (let m = DAY_START; m <= DAY_END; m += 60) hours.push(m);

  const gaps: { s: number; e: number }[] = [];
  const sorted = [...plan].sort((a: any, b: any) => a.start - b.start);
  for (let i = 0; i < sorted.length - 1; i++) { const g0 = sorted[i].end, g1 = sorted[i + 1].start; if (g1 - g0 >= 60) gaps.push({ s: g0, e: g1 }); }

  const segRef = useRef<HTMLDivElement>(null);
  const [thumb, setThumb] = useState({ left: 3, width: 0 });
  useEffect(() => {
    if (!segRef.current) return;
    const btns = segRef.current.querySelectorAll("button");
    const el = btns[view === "plan" ? 0 : 1] as HTMLElement;
    if (el) setThumb({ left: el.offsetLeft, width: el.offsetWidth });
  }, [view, expanded, span]);

  // Inline "Togi listening" popover — records real audio right at the tapped spot.
  const startListen = async (clientX: number, clientY: number, target: any, label: string) => {
    const ctx = buildCtx(target);
    const r = trackRef.current!.getBoundingClientRect();
    setListen({ x: clientX - r.left, y: clientY - r.top, ctx, label, busy: false });
    try { await rec.start(); } catch { setListen(null); onType(ctx); } // mic blocked → type fallback
  };
  const submitListen = async () => {
    if (!listen) return;
    const ctx = listen.ctx;
    setListen((l: any) => (l ? { ...l, busy: true } : l));
    const blob = await rec.stop();
    setListen(null);
    try { const res = await onVoice(ctx, { blob }); if (res && res.status === "clarify") onType(ctx); }
    catch { onType(ctx); }
  };
  const cancelListen = () => { rec.cancel(); setListen(null); };
  const typeListen = () => { const ctx = listen?.ctx; rec.cancel(); setListen(null); if (ctx) onType(ctx); };

  const onBlock = (e: React.MouseEvent, b: any) => { e.stopPropagation(); startListen(e.clientX, e.clientY, { block: b }, b.title); };

  useEffect(() => {
    if (!listen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") { e.preventDefault(); cancelListen(); }
      else if (e.key === "Enter" && !e.shiftKey && !listen.busy) { e.preventDefault(); submitListen(); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [listen]);

  const onTrackDown = (e: React.PointerEvent) => {
    if ((e.target as HTMLElement).closest(".blk") || (e.target as HTMLElement).closest(".listen")) return;
    const r = trackRef.current!.getBoundingClientRect();
    const y0 = e.clientY - r.top;
    let moved = false;
    const move = (ev: PointerEvent) => { moved = true; setDrag({ y0, y1: ev.clientY - r.top }); };
    const up = (ev: PointerEvent) => {
      window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up);
      const y1 = ev.clientY - r.top; setDrag(null);
      if (moved && Math.abs(y1 - y0) > 10) { const a = mOf(Math.min(y0, y1)), b = mOf(Math.max(y0, y1)); startListen(ev.clientX, ev.clientY, { range: [a, b] }, `${fmt(a)}–${fmt(b)}`); }
      else { const t = mOf(y0); startListen(ev.clientX, ev.clientY, { point: t }, `around ${fmt(t)}`); }
    };
    window.addEventListener("pointermove", move); window.addEventListener("pointerup", up);
  };

  return (
    <div className={"cal" + (expanded ? " expanded" : " mini-mode")}>
      <div className="cal-head">
        <div className="cal-head-left"><div className="cal-eyebrow">{dayLabel(selectedDate)}{isToday ? " · today" : ""}</div><DaySelector selectedDate={selectedDate} onSelectDay={onSelectDay} onPlanDay={onPlanDay} /></div>
        <div className="cal-head-right">
          {expanded && (
            <div className="span-seg">
              {["1d", "3d", "wk"].map((s) => (<button key={s} className={span === s ? "on" : ""} onClick={() => setSpan(s)}>{s === "1d" ? "Day" : s === "3d" ? "3-day" : "Week"}</button>))}
            </div>
          )}
          <button className="cal-min" title={expanded ? "Minimize" : "Expand"} onClick={() => setExpanded((v) => !v)}>{expanded ? <IcMinimize size={15} /> : <IcExpand size={15} />}</button>
        </div>
      </div>

      <div className="seg cal-toggle" ref={segRef}>
        <span className="seg-thumb" style={{ left: thumb.left, width: thumb.width }} />
        <button className={view === "plan" ? "on" : ""} onClick={() => setView("plan")}><span className="dot" style={{ background: "var(--cat-deepwork)" }} /> Plan</button>
        <button className={view === "real" ? "on" : ""} onClick={() => setView("real")}><span className="dot" style={{ background: "var(--cat-scroll)" }} /> Real</button>
      </div>

      {!expanded ? (
        <MinimizedDay view={view} real={real} plan={plan} onExpand={() => setExpanded(true)} onTalkBlock={(b: any) => onType(buildCtx({ block: b }))} />
      ) : span !== "1d" ? (
        <div className="cal-track-wrap"><MultiDay span={span} plan={plan} /></div>
      ) : (
        <div className="cal-track-wrap">
          <div className="cal-gutter" style={{ height: trackH }}>{hours.map((m) => <div key={m} className="cal-hr num" style={{ top: yOf(m) }}>{fmt(m)}</div>)}</div>
          <div className="cal-track" ref={trackRef} style={{ height: trackH }} onPointerDown={onTrackDown}>
            {hours.map((m) => <div key={m} className="cal-line" style={{ top: yOf(m) }} />)}

            {view === "plan" && gaps.map((g, i) => (
              <div key={i} className="cal-gap" style={{ top: yOf(g.s), height: yOf(g.e) - yOf(g.s) }}><span className="cal-gap-label"><IcPlus size={12} /> Untracked · tap to tell Togi</span></div>
            ))}

            {isToday && now >= DAY_START && now <= DAY_END && (<div className="cal-now" style={{ top: yOf(now) }}><span className="cal-now-dot" /><span className="cal-now-label num">now</span></div>)}

            {plan.length === 0 && real.length === 0 && (
              <div className="cal-empty" style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center", color: "var(--togi-muted)", pointerEvents: "none", fontSize: 13 }}>
                Nothing on {dayLabel(selectedDate)} yet — tap the <strong style={{ margin: "0 4px" }}>+</strong> on the day, or a gap, to plan.
              </div>
            )}

            <div className="cal-stage" data-view={view}>
              <div className="plan-layer">
                {plan.map((p: any) => (
                  <BlockEl key={p.id} layer="plan" top={yOf(p.start)} height={yOf(p.end) - yOf(p.start)}
                    domain={p.domain} title={p.title} project={p.project} note={p.note} time={`${fmt(p.start)}–${fmt(p.end)}`}
                    editable={p.source === "gcal" && !!onEditBlock} onEdit={(e: any) => { e.stopPropagation(); onEditBlock(p); }}
                    onClick={(e: any) => onBlock(e, p)} />
                ))}
              </div>
              <div className="real-layer">
                {real.map((r: RealEntry) => {
                  const p = r.slot ? plan.find((x: any) => x.id === r.slot) : null;
                  const s = p ? p.start : (r.start ?? 12 * 60);
                  const e2 = p ? p.end : (r.end ?? 13 * 60);
                  const tag = r.off ? "unplanned" : r.match ? "match" : "off";
                  return (
                    <div key={r.id} className={"real-pos" + (p ? " aligned" : "")} style={{ position: "absolute", top: yOf(s), left: 0, right: 0, height: yOf(e2) - yOf(s) }}>
                      <BlockEl layer="real" top={0} height={yOf(e2) - yOf(s)} domain={r.domain} title={r.title} project={r.project} note={r.note}
                        time={`${fmt(s)}–${fmt(e2)}`} tag={tag} live={r.live} onClick={(ev: any) => onBlock(ev, { ...r, start: s, end: e2 })} />
                    </div>
                  );
                })}
              </div>
            </div>

            {drag && (<div className="cal-select" style={{ top: Math.min(drag.y0, drag.y1), height: Math.abs(drag.y1 - drag.y0) }}><span className="num">{fmt(mOf(Math.min(drag.y0, drag.y1)))}–{fmt(mOf(Math.max(drag.y0, drag.y1)))}</span></div>)}

            {listen && (
              <div className="listen" style={{ left: Math.min(listen.x, (trackRef.current?.offsetWidth || 400) - 168), top: Math.max(listen.y - 58, 0) }}>
                <img className="listen-mascot bg-bob" src="/togi-mascot.png" alt="" />
                <div className="listen-card">
                  <div className="listen-bubble"><span className="listen-wave"><i /><i /><i /><i /></span> {listen.busy ? "Saving…" : "Listening…"} <span className="dim">{listen.label}</span></div>
                  <div style={{ display: "flex", gap: 6 }}>
                    <button className="listen-type" onClick={(e) => { e.stopPropagation(); typeListen(); }}><IcChat size={12} /> type instead</button>
                    {!listen.busy && <button className="listen-type" onClick={(e) => { e.stopPropagation(); submitListen(); }} style={{ background: "var(--togi-live)", color: "#fff", borderColor: "transparent" }}>done · enter</button>}
                  </div>
                </div>
                <button className="listen-x" title="cancel" onClick={(e) => { e.stopPropagation(); cancelListen(); }}><IcClose size={12} /></button>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
