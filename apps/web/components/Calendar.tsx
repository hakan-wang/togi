/* ============================================================
   Togi — DayCalendar. Real dates + real clock. Plan / Real toggle.
   Tap an EVENT → an info menu (edit / delete). Drag an event up/down to
   reschedule. Tap or drag an EMPTY space → the voice "listening" popover.
   Overlapping events lay out side-by-side in columns (like Google Calendar).
   ============================================================ */
"use client";
import * as React from "react";
import { useEffect, useRef, useState } from "react";
import { DOMAINS, DAY_START, DAY_END, PLAN, RealEntry, REAL_SEED, UPCOMING, fmt } from "../lib/data";
import { dayKey, dayLabel, weekDays, WeekDay } from "../lib/dates";
import { IcCheck, IcClose, IcChat, IcExpand, IcMinimize, IcPlus, IcEdit, IcTrash } from "./icons";
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

/* Pack overlapping items into side-by-side columns (Google-Calendar style).
   Returns, aligned to the input order, each item's { col, cols } within its overlap cluster. */
function packColumns(items: { start: number; end: number }[]): { col: number; cols: number }[] {
  const order = items.map((it, idx) => ({ idx, start: it.start, end: it.end })).sort((a, b) => a.start - b.start || a.end - b.end);
  const res = items.map(() => ({ col: 0, cols: 1 }));
  let cluster: { idx: number; start: number; end: number }[] = [];
  let clusterEnd = -Infinity;
  const flush = () => {
    const colEnds: number[] = [];
    for (const e of cluster) {
      let c = colEnds.findIndex((end) => end <= e.start);
      if (c === -1) { c = colEnds.length; colEnds.push(e.end); } else { colEnds[c] = e.end; }
      res[e.idx].col = c;
    }
    for (const e of cluster) res[e.idx].cols = colEnds.length;
    cluster = []; clusterEnd = -Infinity;
  };
  for (const e of order) {
    if (cluster.length && e.start >= clusterEnd) flush();
    cluster.push(e); clusterEnd = Math.max(clusterEnd, e.end);
  }
  flush();
  return res;
}

/* Inline left/width for a block in its column (empty when there's no overlap → CSS defaults apply). */
function colPos(leftBase: number, rightBase: number, col: number, cols: number): React.CSSProperties {
  if (cols <= 1) return {};
  const gap = 3;
  return {
    left: `calc(${leftBase}px + ${col} * (100% - ${leftBase + rightBase}px) / ${cols})`,
    width: `calc((100% - ${leftBase + rightBase}px) / ${cols} - ${gap}px)`,
    right: "auto",
  };
}

function BlockEl({ top, height, domain, title, project, note, time, layer, tag, live, onDown, posStyle, dragging }: any) {
  const C = DOMAINS[domain];
  const tiny = height < 40;
  const shortBlk = Math.max(height, 22) < 34;   // tighten the grips so both still fit a small block
  return (
    <div className={"blk blk-" + layer + (tag ? " has-tag" : "") + (live ? " blk-live" : "") + (dragging ? " blk-dragging" : "")}
      style={{ top, height: Math.max(height, 22), background: C.tint, ["--c" as any]: C.color, ...posStyle }} onPointerDown={(e: any) => onDown(e, null)}>
      <span className="blk-rail" />
      <span className={"blk-handle blk-handle-top" + (shortBlk ? " blk-handle-sm" : "")} title="Drag to change the start" onPointerDown={(e: any) => { e.stopPropagation(); onDown(e, "top"); }} />
      <span className={"blk-handle blk-handle-bottom" + (shortBlk ? " blk-handle-sm" : "")} title="Drag to change the end" onPointerDown={(e: any) => { e.stopPropagation(); onDown(e, "bottom"); }} />
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

export function DayCalendar({ view, setView, real = REAL_SEED, plan = PLAN, now = 0, selectedDate, onSelectDay, onPlanDay, buildCtx, onVoice, onType, onEventEdit, onEventDelete, onEventMove, density }: any) {
  const [expanded, setExpanded] = useState(true);
  const [span, setSpan] = useState("1d");
  const [listen, setListen] = useState<any>(null);  // { x, y, ctx, label, busy }
  const [drag, setDrag] = useState<any>(null);       // empty-space drag-select preview
  const [menu, setMenu] = useState<any>(null);       // tapped-event info menu { kind, block, x, y }
  const [moving, setMoving] = useState<any>(null);   // event being dragged to a new time { kind, id, newStart, newEnd }
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

  // Column layout for overlapping events (per layer).
  const planLayout = packColumns(plan.map((p: any) => ({ start: p.start, end: p.end })));
  const realResolved = real.map((r: RealEntry) => {
    const p = r.slot ? plan.find((x: any) => x.id === r.slot) : null;
    return { r, p, s: p ? p.start : (r.start ?? 12 * 60), e2: p ? p.end : (r.end ?? 13 * 60) };
  });
  const realLayout = packColumns(realResolved.map((x: any) => ({ start: x.s, end: x.e2 })));

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
    const ctx = listen.ctx; const draftText = listen.draftText;
    setListen((l: any) => (l ? { ...l, busy: true } : l));
    const blob = await rec.stop();
    try {
      const res = await onVoice(ctx, { blob, draftText });
      if (res && res.status === "clarify") {
        // one floating-chat question — keep the popover open and listening for the answer
        setListen((l: any) => (l ? { ...l, busy: false, question: res.question, draftText: res.draftText, label: "answer Togi" } : l));
        try { await rec.start(); } catch { setListen(null); onType(ctx); }
        return;
      }
    } catch { /* fall through to close */ }
    setListen(null);
  };
  const cancelListen = () => { rec.cancel(); setListen(null); };
  const typeListen = () => { const ctx = listen?.ctx; rec.cancel(); setListen(null); if (ctx) onType(ctx); };

  // Tap an event = open its menu. Drag the body = reschedule (move). Drag the top/bottom
  // grip = resize the start/end. All snap to 5-minute steps.
  const MIN_DUR = 10;
  const onBlockDown = (e: React.PointerEvent, kind: "plan" | "real", block: any, edge: "top" | "bottom" | null) => {
    if (e.button !== 0) return;
    e.stopPropagation();
    e.preventDefault();
    const startClientY = e.clientY;
    const origStart = block.start, origEnd = block.end, dur = origEnd - origStart;
    let moved = false;
    const compute = (dy: number): { ns: number; ne: number } => {
      if (edge === "top") { const ns = Math.max(DAY_START, Math.min(origEnd - MIN_DUR, mOf(yOf(origStart) + dy))); return { ns, ne: origEnd }; }
      if (edge === "bottom") { const ne = Math.min(DAY_END, Math.max(origStart + MIN_DUR, mOf(yOf(origEnd) + dy))); return { ns: origStart, ne }; }
      const ns = Math.max(DAY_START, Math.min(DAY_END - dur, mOf(yOf(origStart) + dy)));
      return { ns, ne: ns + dur };
    };
    const move = (ev: PointerEvent) => {
      const dy = ev.clientY - startClientY;
      if (!moved && Math.abs(dy) > 4) moved = true;
      if (moved) { const { ns, ne } = compute(dy); setMoving({ kind, id: block.id, newStart: ns, newEnd: ne }); }
    };
    const up = (ev: PointerEvent) => {
      window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up);
      setMoving(null);
      if (moved) { const { ns, ne } = compute(ev.clientY - startClientY); if (ns !== origStart || ne !== origEnd) onEventMove(kind, block, ns, ne); }
      else { const rect = trackRef.current!.getBoundingClientRect(); setMenu({ kind, block, x: e.clientX - rect.left, y: e.clientY - rect.top }); }
    };
    window.addEventListener("pointermove", move); window.addEventListener("pointerup", up);
  };

  useEffect(() => {
    if (!listen) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") { e.preventDefault(); cancelListen(); }
      else if (e.key === "Enter" && !e.shiftKey && !listen.busy) { e.preventDefault(); submitListen(); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [listen]);

  // Close the event menu when clicking anywhere that isn't the menu or a block.
  useEffect(() => {
    if (!menu) return;
    const onDown = (e: PointerEvent) => { const t = e.target as HTMLElement; if (!t.closest(".ev-menu") && !t.closest(".blk")) setMenu(null); };
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") setMenu(null); };
    window.addEventListener("pointerdown", onDown); window.addEventListener("keydown", onKey);
    return () => { window.removeEventListener("pointerdown", onDown); window.removeEventListener("keydown", onKey); };
  }, [menu]);

  const onTrackDown = (e: React.PointerEvent) => {
    if (menu) { setMenu(null); return; }          // first tap on empty space just dismisses the menu
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

            {view === "plan" && gaps.map((g, i) => {
              // A gap you can still act on in the future is for PLANNING; a gap in the past is
              // untracked time to tell Togi about. (You can't track the future.)
              const plannable = selectedDate > dayKey() || (selectedDate === dayKey() && g.e > now);
              return (
                <div key={i} className="cal-gap" style={{ top: yOf(g.s), height: yOf(g.e) - yOf(g.s) }}>
                  <span className="cal-gap-label"><IcPlus size={12} /> {plannable ? "Unplanned · tap to plan with Togi" : "Untracked · tap to tell Togi"}</span>
                </div>
              );
            })}

            {isToday && now >= DAY_START && now <= DAY_END && (<div className="cal-now" style={{ top: yOf(now) }}><span className="cal-now-dot" /><span className="cal-now-label num">now</span></div>)}

            {plan.length === 0 && real.length === 0 && (
              <div className="cal-empty" style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center", color: "var(--togi-muted)", pointerEvents: "none", fontSize: 13 }}>
                Nothing on {dayLabel(selectedDate)} yet — tap the <strong style={{ margin: "0 4px" }}>+</strong> on the day, or a gap, to plan.
              </div>
            )}

            <div className="cal-stage" data-view={view}>
              <div className="plan-layer">
                {plan.map((p: any, i: number) => {
                  const L = planLayout[i];
                  const m = moving && moving.kind === "plan" && moving.id === p.id ? moving : null;
                  const ps = m ? m.newStart : p.start, pe = m ? m.newEnd : p.end;
                  return (
                    <BlockEl key={p.id} layer="plan" top={yOf(ps)} height={yOf(pe) - yOf(ps)}
                      domain={p.domain} title={p.title} project={p.project} note={p.note} time={`${fmt(ps)}–${fmt(pe)}`}
                      posStyle={colPos(8, 10, L.col, L.cols)} dragging={!!m}
                      onDown={(e: any, edge: any) => onBlockDown(e, "plan", p, edge)} />
                  );
                })}
              </div>
              <div className="real-layer">
                {realResolved.map(({ r, p, s, e2 }: any, i: number) => {
                  const L = realLayout[i];
                  const tag = r.off ? "unplanned" : r.match ? "match" : "off";
                  const m = moving && moving.kind === "real" && moving.id === r.id ? moving : null;
                  const rs = m ? m.newStart : s, re = m ? m.newEnd : e2;
                  return (
                    <div key={r.id} className={"real-pos" + (p ? " aligned" : "")} style={{ position: "absolute", top: yOf(rs), left: 0, right: 0, height: yOf(re) - yOf(rs) }}>
                      <BlockEl layer="real" top={0} height={yOf(re) - yOf(rs)} domain={r.domain} title={r.title} project={r.project} note={r.note}
                        time={`${fmt(rs)}–${fmt(re)}`} tag={tag} live={r.live} posStyle={colPos(22, 8, L.col, L.cols)} dragging={!!m}
                        onDown={(ev: any, edge: any) => onBlockDown(ev, "real", { ...r, start: s, end: e2 }, edge)} />
                    </div>
                  );
                })}
              </div>
            </div>

            {drag && (<div className="cal-select" style={{ top: Math.min(drag.y0, drag.y1), height: Math.abs(drag.y1 - drag.y0) }}><span className="num">{fmt(mOf(Math.min(drag.y0, drag.y1)))}–{fmt(mOf(Math.max(drag.y0, drag.y1)))}</span></div>)}

            {menu && (() => {
              const b = menu.block; const C = DOMAINS[b.domain as keyof typeof DOMAINS];
              const W = 212;
              const left = Math.max(6, Math.min(menu.x, (trackRef.current?.offsetWidth || 400) - W - 6));
              const top = Math.max(4, menu.y - 8);
              const where = b.source === "gcal" ? (b.calendar || "Google Calendar") : menu.kind === "real" ? "Real check-in" : "Togi plan";
              return (
                <div className="ev-menu" style={{ left, top, width: W }} onPointerDown={(e) => e.stopPropagation()}>
                  <div className="ev-menu-head">
                    <span className="ev-menu-dot" style={{ background: C.color }} />
                    <span className="ev-menu-title">{b.title}</span>
                    <button className="ev-menu-x" title="Close" onClick={() => setMenu(null)}><IcClose size={13} /></button>
                  </div>
                  <div className="ev-menu-time num">{fmt(b.start)}–{fmt(b.end)}</div>
                  {b.project && <div className="ev-menu-sub">{b.project}</div>}
                  {b.note && <div className="ev-menu-sub">{b.note}</div>}
                  <div className="ev-menu-cal"><span className="cat-swatch" style={{ background: C.color }} /> {where}</div>
                  <div className="ev-menu-actions">
                    <button onClick={() => { onEventEdit(menu.kind, b); setMenu(null); }}><IcEdit size={13} /> Edit</button>
                    <button className="danger" onClick={() => { onEventDelete(menu.kind, b); setMenu(null); }}><IcTrash size={13} /> Delete</button>
                  </div>
                </div>
              );
            })()}

            {listen && (
              <div className="listen" style={{ left: Math.min(listen.x, (trackRef.current?.offsetWidth || 400) - 168), top: Math.max(listen.y - 58, 0) }}>
                <img className="listen-mascot bg-bob" src="/togi-mascot.png" alt="" />
                <div className="listen-card">
                  {listen.question && <div style={{ color: "rgba(255,255,255,0.92)", fontSize: 12, lineHeight: 1.35, marginBottom: 7 }}>Togi: {listen.question}</div>}
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
