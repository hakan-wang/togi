/* ============================================================
   Togi — DayCalendar (ported). Plan / Real with a rack-focus toggle.
   Real sits at the same Y as its Plan block, offset on X, faint Plan behind.
   Tap empties / drag → self check-in. The Real layer is driven by a prop so
   live check-ins appear immediately.
   ============================================================ */
"use client";
import * as React from "react";
import { useEffect, useRef, useState } from "react";
import { CATEGORIES, DAY_START, DAY_END, NOW, PLAN, RealEntry, REAL_SEED, UPCOMING, fmt, hm, CategoryKey } from "../lib/data";
import { IcCheck, IcClose, IcChat, IcExpand, IcMinimize, IcPlus } from "./icons";

const WEEK = [
  { d: "Mon", n: 2 }, { d: "Tue", n: 3 }, { d: "Wed", n: 4 },
  { d: "Thu", n: 5, today: true },
  { d: "Fri", n: 6, future: true }, { d: "Sat", n: 7, future: true }, { d: "Sun", n: 8, future: true },
];

function DaySelector({ onPlanDay }: any) {
  return (
    <div className="day-strip">
      {WEEK.map((w: any) => (
        <button key={w.d} className={"day-cell" + (w.today ? " today" : "") + (w.future ? " future" : "")}
          onClick={() => w.future && onPlanDay(w)} title={w.future ? "Plan this day with Togi" : ""}>
          <span className="day-cell-d">{w.d}</span>
          <span className="day-cell-n num">{w.n}</span>
          {w.future && <span className="day-cell-plan"><IcPlus size={11} /></span>}
        </button>
      ))}
    </div>
  );
}

function BlockEl({ top, height, cat, title, sub, time, layer, tag, live, onClick }: any) {
  const C = CATEGORIES[cat as CategoryKey];
  const tiny = height < 40;
  return (
    <div className={"blk blk-" + layer + (tag ? " has-tag" : "") + (live ? " blk-live" : "")}
      style={{ top, height: Math.max(height, 22), background: C.tint, ["--c" as any]: C.color }} onClick={onClick}>
      <span className="blk-rail" />
      <div className="blk-body">
        <div className="blk-row">
          <span className="blk-title">{title}</span>
          {tag === "off" && <span className="blk-leak-tag">off-plan</span>}
          {tag === "match" && <span className="blk-check"><IcCheck size={11} /></span>}
          {tag === "unplanned" && <span className="blk-unplanned">unplanned</span>}
          {live && <span className="blk-unplanned">just logged</span>}
        </div>
        {!tiny && (
          <div className="blk-meta">
            <span className="blk-time num">{time}</span>
            {sub && <span className="blk-sub">{sub}</span>}
          </div>
        )}
      </div>
    </div>
  );
}

function realStart(r: RealEntry): number { const p = r.slot ? PLAN.find((x) => x.id === r.slot) : null; return p ? p.start : (r.start ?? NOW); }

function MinimizedDay({ view, real, onExpand, onTalkBlock }: any) {
  const list = view === "plan" ? PLAN : [...real].sort((a: RealEntry, b: RealEntry) => realStart(a) - realStart(b));
  return (
    <div className="mini">
      <div className="mini-list">
        {list.slice(0, 5).map((b: any) => {
          const C = CATEGORIES[b.cat as CategoryKey];
          return (
            <button className="mini-row" key={b.id} onClick={() => onTalkBlock(b)}>
              <span className="mini-time num">{fmt(view === "plan" ? b.start : realStart(b))}</span>
              <span className="mini-rail" style={{ background: C.color }} />
              <span className="mini-title">{b.title}</span>
            </button>
          );
        })}
      </div>
      <div className="mini-up">
        <div className="mini-up-h">Coming up</div>
        {UPCOMING.map((u, i) => {
          const C = CATEGORIES[u.cat];
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

function MultiDay({ span }: { span: string }) {
  const days = span === "3d" ? WEEK.filter((w) => ["Thu", "Fri", "Sat"].includes(w.d)) : WEEK;
  const ppm = 0.5;
  const H = (DAY_END - DAY_START) * ppm;
  const yOf = (m: number) => (m - DAY_START) * ppm;
  const labels: number[] = [];
  for (let m = DAY_START; m <= DAY_END; m += 120) labels.push(m);
  // deterministic, varied blocks per day so the week looks lived-in (today = the real plan)
  const dayBlocks = (idx: number, isToday: boolean) => (isToday ? PLAN : PLAN.filter((_, k) => (k + idx) % 3 !== 0));
  return (
    <div className="multi" style={{ height: H + 34 }}>
      <div className="multi-gutter" style={{ height: H }}>
        {labels.map((m) => <div key={m} className="multi-hr num" style={{ top: yOf(m) }}>{fmt(m)}</div>)}
      </div>
      {days.map((w: any, i: number) => {
        const isToday = !!w.today;
        return (
          <div className="multi-col" key={w.d}>
            <div className={"multi-col-h" + (isToday ? " today" : "")}>
              <span className="multi-col-d">{w.d}</span> <span className="multi-col-n num">{w.n}</span>
            </div>
            <div className="multi-track" style={{ height: H }}>
              {labels.map((m) => <div key={m} className="multi-line" style={{ top: yOf(m) }} />)}
              {dayBlocks(i, isToday).map((b) => {
                const C = CATEGORIES[b.cat];
                return <div className="multi-blk" key={b.id} title={`${C.label} · ${b.title}`}
                  style={{ top: yOf(b.start), height: Math.max((b.end - b.start) * ppm, 11), background: C.color, opacity: isToday ? 1 : 0.8 }} />;
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
}

export function DayCalendar({ view, setView, real = REAL_SEED, onPlanDay, onSelfCheckin, onTalkBlock, density }: any) {
  const [expanded, setExpanded] = useState(true);
  const [span, setSpan] = useState("1d");
  const [listen, setListen] = useState<any>(null);
  const [drag, setDrag] = useState<any>(null);
  const trackRef = useRef<HTMLDivElement>(null);

  const ppm = density === "compact" ? 0.62 : density === "comfy" ? 0.82 : 0.72;
  const now = NOW;
  const trackH = (DAY_END - DAY_START) * ppm;
  const yOf = (m: number) => (m - DAY_START) * ppm;
  const mOf = (y: number) => Math.round((y / ppm + DAY_START) / 5) * 5;

  const hours: number[] = [];
  for (let m = DAY_START; m <= DAY_END; m += 60) hours.push(m);

  const gaps: { s: number; e: number }[] = [];
  const sorted = [...PLAN].sort((a, b) => a.start - b.start);
  for (let i = 0; i < sorted.length - 1; i++) {
    const g0 = sorted[i].end, g1 = sorted[i + 1].start;
    if (g1 - g0 >= 60) gaps.push({ s: g0, e: g1 });
  }

  const segRef = useRef<HTMLDivElement>(null);
  const [thumb, setThumb] = useState({ left: 3, width: 0 });
  useEffect(() => {
    if (!segRef.current) return;
    const btns = segRef.current.querySelectorAll("button");
    const el = btns[view === "plan" ? 0 : 1] as HTMLElement;
    if (el) setThumb({ left: el.offsetLeft, width: el.offsetWidth });
  }, [view, expanded, span]);

  const talkAt = (clientX: number, clientY: number, label: string, fn: () => void) => {
    const r = trackRef.current!.getBoundingClientRect();
    setListen({ x: clientX - r.left, y: clientY - r.top, label, fn });
  };
  const onBlock = (e: React.MouseEvent, b: any, label: string) => { e.stopPropagation(); talkAt(e.clientX, e.clientY, label, () => onTalkBlock(b)); };

  useEffect(() => {
    if (!listen) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape" || e.key === "Enter") { e.preventDefault(); setListen(null); } };
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
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      const y1 = ev.clientY - r.top;
      setDrag(null);
      if (moved && Math.abs(y1 - y0) > 10) {
        const a = mOf(Math.min(y0, y1)), b = mOf(Math.max(y0, y1));
        talkAt(ev.clientX, ev.clientY, `${fmt(a)}–${fmt(b)}`, () => onSelfCheckin(`${fmt(a)}–${fmt(b)}`));
      } else {
        const t = mOf(y0);
        talkAt(ev.clientX, ev.clientY, `around ${fmt(t)}`, () => onSelfCheckin(`around ${fmt(t)}`));
      }
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  };

  return (
    <div className={"cal" + (expanded ? " expanded" : " mini-mode")}>
      <div className="cal-head">
        <div className="cal-head-left">
          <div className="cal-eyebrow">Thursday · 5 June</div>
          <DaySelector onPlanDay={onPlanDay} />
        </div>
        <div className="cal-head-right">
          {expanded && (
            <div className="span-seg">
              {["1d", "3d", "wk"].map((s) => (
                <button key={s} className={span === s ? "on" : ""} onClick={() => setSpan(s)}>{s === "1d" ? "Day" : s === "3d" ? "3-day" : "Week"}</button>
              ))}
            </div>
          )}
          <button className="cal-min" title={expanded ? "Minimize" : "Expand"} onClick={() => setExpanded((v) => !v)}>
            {expanded ? <IcMinimize size={15} /> : <IcExpand size={15} />}
          </button>
        </div>
      </div>

      <div className="seg cal-toggle" ref={segRef}>
        <span className="seg-thumb" style={{ left: thumb.left, width: thumb.width }} />
        <button className={view === "plan" ? "on" : ""} onClick={() => setView("plan")}><span className="dot" style={{ background: "var(--cat-deepwork)" }} /> Plan</button>
        <button className={view === "real" ? "on" : ""} onClick={() => setView("real")}><span className="dot" style={{ background: "var(--cat-scroll)" }} /> Real</button>
      </div>

      {!expanded ? (
        <MinimizedDay view={view} real={real} onExpand={() => setExpanded(true)} onTalkBlock={onTalkBlock} />
      ) : span !== "1d" ? (
        <div className="cal-track-wrap"><MultiDay span={span} /></div>
      ) : (
        <div className="cal-track-wrap">
          <div className="cal-gutter" style={{ height: trackH }}>
            {hours.map((m) => <div key={m} className="cal-hr num" style={{ top: yOf(m) }}>{fmt(m)}</div>)}
          </div>
          <div className="cal-track" ref={trackRef} style={{ height: trackH }} onPointerDown={onTrackDown}>
            {hours.map((m) => <div key={m} className="cal-line" style={{ top: yOf(m) }} />)}

            {view === "plan" && gaps.map((g, i) => (
              <div key={i} className="cal-gap" style={{ top: yOf(g.s), height: yOf(g.e) - yOf(g.s) }}>
                <span className="cal-gap-label"><IcPlus size={12} /> Untracked · tap to tell Togi</span>
              </div>
            ))}

            {now >= DAY_START && now <= DAY_END && (
              <div className="cal-now" style={{ top: yOf(now) }}><span className="cal-now-dot" /><span className="cal-now-label num">now</span></div>
            )}

            <div className="cal-stage" data-view={view}>
              <div className="plan-layer">
                {PLAN.map((p) => (
                  <BlockEl key={p.id} layer="plan" top={yOf(p.start)} height={yOf(p.end) - yOf(p.start)}
                    cat={p.cat} title={p.title} sub={p.sub} time={`${fmt(p.start)}–${fmt(p.end)}`} onClick={(e: any) => onBlock(e, p, p.title)} />
                ))}
              </div>
              <div className="real-layer">
                {real.map((r: RealEntry) => {
                  const p = r.slot ? PLAN.find((x) => x.id === r.slot) : null;
                  const s = p ? p.start : (r.start ?? NOW);
                  const e2 = p ? p.end : (r.end ?? NOW);
                  const tag = r.off ? "unplanned" : r.match ? "match" : "off";
                  return (
                    <div key={r.id} className={"real-pos" + (p ? " aligned" : "")} style={{ position: "absolute", top: yOf(s), left: 0, right: 0, height: yOf(e2) - yOf(s) }}>
                      <BlockEl layer="real" top={0} height={yOf(e2) - yOf(s)} cat={r.cat} title={r.title} sub={r.sub}
                        time={`${fmt(s)}–${fmt(e2)}`} tag={tag} live={r.live} onClick={(ev: any) => onBlock(ev, { ...r, start: s, end: e2 }, r.title)} />
                    </div>
                  );
                })}
              </div>
            </div>

            {drag && (
              <div className="cal-select" style={{ top: Math.min(drag.y0, drag.y1), height: Math.abs(drag.y1 - drag.y0) }}>
                <span className="num">{fmt(mOf(Math.min(drag.y0, drag.y1)))}–{fmt(mOf(Math.max(drag.y0, drag.y1)))}</span>
              </div>
            )}

            {listen && (
              <div className="listen" style={{ left: Math.min(listen.x, (trackRef.current?.offsetWidth || 400) - 168), top: Math.max(listen.y - 58, 0) }}>
                <img className="listen-mascot bg-bob" src="/togi-mascot.png" alt="" />
                <div className="listen-card">
                  <div className="listen-bubble"><span className="listen-wave"><i /><i /><i /><i /></span> Listening… <span className="dim">{listen.label}</span></div>
                  <button className="listen-type" onClick={(e) => { e.stopPropagation(); const f = listen.fn; setListen(null); f(); }}><IcChat size={12} /> type instead</button>
                </div>
                <button className="listen-x" title="stop" onClick={(e) => { e.stopPropagation(); setListen(null); }}><IcClose size={12} /></button>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
