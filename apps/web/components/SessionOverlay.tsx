/* ============================================================
   Togi — Session overlay: the voice-first check-in / planning / ask moment.
   Scripted, branchy demo (planning/ask/self may be scripted per the spec).
   The PRIMARY live check-in is the Today card; this overlay covers the other modes
   and acts as a fallback entry point from the dock / Sessions tab.
   ============================================================ */
"use client";
import * as React from "react";
import { useEffect, useRef, useState } from "react";
import { CATEGORIES, DOMAINS, Domain, PLAN, REAL_SEED, RealEntry } from "../lib/data";
import { MessageBubble, Composer } from "./ds";
import { IcArrow, IcArrowUp, IcClose, IcMic } from "./icons";

const NODES: any = {
  c0: { say: "Your Litro block just ended — the formula doc. Did you actually get it done?", opts: [["Pretty much", "cDone"], ["Only started it", "c1"], ["Did something else", "c1b"]] },
  c1: { say: "Honest — that’s the whole point. Roughly how long did you spend on it?", opts: [["~50 minutes", "c2"], ["Less than that", "c2"]] },
  c1b: { say: "No stress, it happens. So what did you do instead?", opts: [["Scrolling, tbh", "c3"], ["Tidied my desk", "c3b"]] },
  c2: { say: "Okay. And the rest of that block — where did it actually go?", opts: [["Scrolling, tbh", "c3"], ["Tidied my desk", "c3b"]] },
  c3: { say: "Thanks for being straight with me. Here’s how your reality just updated:", card: { type: "cats", rows: [{ cat: "deepwork", sub: "Litro", desc: "Formula doc", time: "50m" }, { cat: "scroll", sub: "TikTok", desc: "“for inspiration”", time: "40m" }] }, note: "You saw it — that’s the win. Awareness comes before change.", done: { label: "See it on Real", action: "real" } },
  c3b: { say: "Logged. Here’s the honest version of that block:", card: { type: "cats", rows: [{ cat: "deepwork", sub: "Litro", desc: "Formula doc", time: "50m" }, { cat: "personal", sub: "Tidying", desc: "Cleaned the desk", time: "40m" }] }, note: "No judgement — now it’s data you can plan around.", done: { label: "See it on Real", action: "real" } },
  cDone: { say: "Nice — momentum. I’ve logged the full block as Deep work › Litro. That’s a real one.", card: { type: "cats", rows: [{ cat: "deepwork", sub: "Litro", desc: "Formula doc", time: "1h 30m" }] }, done: { label: "See it on Real", action: "real" } },

  p0: { say: "Let’s shape tomorrow. Tell me what you actually want to get done — just say it.", input: true, route: "p1" },
  p1: { say: "Good. But I can’t check something vague — how long, and what exactly? Give me a concrete block.", opts: [["2h · the Litro vlog", "p2"], ["1h · email suppliers", "p3L"]] },
  p2: { say: "Here’s the pattern: three mornings running you planned an edit and scrolled instead — then finished it after 3pm. Want me to put it where you actually do it?", opts: [["Yes, after 15:00", "p3"], ["No, keep it morning", "p3m"]] },
  p3: { say: "Added it for the afternoon, when you’re honest with yourself:", card: { type: "cats", rows: [{ cat: "creative", sub: "Editing", desc: "Litro vlog", time: "15:00–17:00" }] }, note: "Anything else for tomorrow?", opts: [["Add the gym", "pGym"], ["That’s enough", "p4"]] },
  p3m: { say: "Your call — it’s your plan. Logged it for the morning. I’ll check in when it ends.", card: { type: "cats", rows: [{ cat: "creative", sub: "Editing", desc: "Litro vlog", time: "09:00–11:00" }] }, opts: [["Add the gym", "pGym"], ["That’s enough", "p4"]] },
  pLitro: { say: "Litro — what part exactly? “Work on Litro” is too broad to check.", opts: [["Formula v3, 1h", "p3L"], ["Email suppliers, 30m", "p3L"]] },
  p3L: { say: "Good — concrete and checkable. Added:", card: { type: "cats", rows: [{ cat: "deepwork", sub: "Litro", desc: "Formula v3", time: "11:00–12:00" }] }, opts: [["Add the gym", "pGym"], ["That’s enough", "p4"]] },
  pGym: { say: "Easy one. Mornings work for the gym — you keep that one.", card: { type: "cats", rows: [{ cat: "health", sub: "Gym", desc: "Strength", time: "07:30–08:15" }] }, opts: [["See friends too", "pFr"], ["That’s enough", "p4"]] },
  pFr: { say: "Good — it’s not all work. Roughly when?", card: { type: "cats", rows: [{ cat: "social", sub: "Friends", desc: "Evening", time: "19:00–21:00" }] }, opts: [["That’s enough", "p4"]] },
  p4: { say: "One last thing — you’ve planned “Read 30 pages” three times and never done it. Keep it for tomorrow, or let it go?", opts: [["Keep it", "p5"], ["Let it go", "p5d"]] },
  p5: { say: "Kept it — I’ll slot it in. Tomorrow’s taking shape: real blocks, categorized, and built around how you actually work.", done: { label: "Open tomorrow’s plan", action: "plan" } },
  p5d: { say: "Let go. No guilt — better an honest plan than a haunted one. Tomorrow’s set.", done: { label: "Open tomorrow’s plan", action: "plan" } },

  sf0: { say: "Nothing was planned {ctx}. No judgement — what did you actually get up to?", opts: [["Errands + lunch", "sf1"], ["Scrolled, honestly", "sf2"], ["Worked on Litro", "sf3"]], input: true, route: "sf1" },
  sf1: { say: "Logged it honestly — here’s that stretch:", card: { type: "cats", rows: [{ cat: "errands", sub: "Town", desc: "Post office + lunch", time: "1h 10m" }, { cat: "leisure", sub: "Meals", desc: "Ate, washed up", time: "40m" }] }, note: "Now that hour isn’t a blank anymore.", done: { label: "See it on Real", action: "real" } },
  sf2: { say: "Thanks for being straight with me — that’s the whole point.", card: { type: "cats", rows: [{ cat: "scroll", sub: "TikTok", desc: "Scrolled", time: "1h" }] }, note: "You saw it. Awareness comes before change.", done: { label: "See it on Real", action: "real" } },
  sf3: { say: "Nice — that counts, and now it’s on the record:", card: { type: "cats", rows: [{ cat: "deepwork", sub: "Litro", desc: "Worked on Litro", time: "1h" }] }, done: { label: "See it on Real", action: "real" } },

  a0: { say: "I’m here. Ask me anything about your time — today, this week, or further back.", openers: ["Where did my time go today?", "How much did I scroll this week?", "Help me plan tomorrow"], optsMap: { "Where did my time go today?": "a1", "How much did I scroll this week?": "a2", "Help me plan tomorrow": "p0" }, input: true },
  a1: { say: "Here’s today, honestly — five of seven blocks landed, but the morning leaked:", card: { type: "breakdown" }, opts: [["Why did editing slip?", "a1b"], ["Plan tomorrow around it", "p2"]] },
  a1b: { say: "You opened TikTok “for inspiration” at 09:20 and it held you for 1h 50m — right through the planned edit. The edit didn’t fail, it moved to 15:10. It usually does.", opts: [["Plan tomorrow around it", "p2"]] },
  a2: { say: "3h 40m of scrolling over four days — and most of it landed inside blocks you’d planned for editing.", card: { type: "scrollweek" }, opts: [["Plan around it", "p2"]] },
};

function CatCard({ rows }: any) {
  return (
    <div className="sx-card">
      {rows.map((r: any, i: number) => {
        const C = CATEGORIES[r.cat as keyof typeof CATEGORIES];
        return (
          <div className="sx-cat" key={i}>
            <span className="sx-rail" style={{ background: C.color }} />
            <div className="sx-cat-body">
              <div className="sx-cat-top"><span className="cat-chip"><span className="cat-swatch" style={{ background: C.color }} />{C.label}</span><span className="sx-time num">{r.time}</span></div>
              <div className="sx-cat-path num">{C.label} › {r.sub} › {r.desc}</div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

function dur(r: RealEntry) { const p = r.slot ? PLAN.find((x) => x.id === r.slot) : null; if (p) return p.end - p.start; return (r.end ?? 0) - (r.start ?? 0); }

function Breakdown() {
  const totals: Record<string, number> = {};
  REAL_SEED.forEach((b) => { totals[b.domain] = (totals[b.domain] || 0) + dur(b); });
  const max = Math.max(...Object.values(totals), 1);
  const order = Object.entries(totals).sort((a, b) => b[1] - a[1]);
  return (
    <div className="sx-card sx-break">
      {order.map(([cat, m]) => {
        const C = DOMAINS[cat as Domain];
        const h = Math.floor(m / 60), mm = m % 60;
        return (
          <div className="brk-row" key={cat}>
            <span className="brk-label"><span className="cat-swatch" style={{ background: C.color }} />{C.label}</span>
            <span className="brk-bar"><span style={{ width: (m / max * 100) + "%", background: C.color }} /></span>
            <span className="brk-val num">{h ? h + "h " : ""}{mm ? mm + "m" : h ? "" : "0m"}</span>
          </div>
        );
      })}
    </div>
  );
}

function ScrollWeek() {
  const days: [string, number][] = [["Mon", 35], ["Tue", 70], ["Wed", 50], ["Thu", 65]];
  const max = 70;
  return (
    <div className="sx-card sx-break">
      {days.map(([d, m]) => (
        <div className="brk-row" key={d}>
          <span className="brk-label num" style={{ minWidth: 40 }}>{d}</span>
          <span className="brk-bar"><span style={{ width: (m / max * 100) + "%", background: "var(--cat-scroll)" }} /></span>
          <span className="brk-val num">{m}m</span>
        </div>
      ))}
    </div>
  );
}

function renderCard(card: any) {
  if (!card) return null;
  if (card.type === "cats") return <CatCard rows={card.rows} />;
  if (card.type === "breakdown") return <Breakdown />;
  if (card.type === "scrollweek") return <ScrollWeek />;
  return null;
}

const MODE_META: any = {
  ask: { label: "Hey Togi", sub: "Voice · ask anything" },
  plan: { label: "Planning session", sub: "≈ 5 min · let’s set tomorrow" },
  checkin: { label: "Check-in", sub: "≈ 2 min · what really happened" },
  self: { label: "Self check-in", sub: "≈ 2 min · log untracked time" },
};

export function SessionOverlay({ mode, ctx, onClose, onAction }: any) {
  const start = mode === "plan" ? "p0" : mode === "checkin" ? "c0" : mode === "self" ? "sf0" : "a0";
  const [history, setHistory] = useState<any[]>([]);
  const [node, setNode] = useState<any>(null);
  const [text, setText] = useState("");
  const scroller = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const n = NODES[start];
    const say = (n.say || "").replace("{ctx}", ctx || "then");
    setHistory([{ from: "coach", text: say, card: n.card, note: n.note }]);
    setNode(n);
  }, [mode]); // eslint-disable-line

  useEffect(() => { if (scroller.current) scroller.current.scrollTop = scroller.current.scrollHeight + 200; }, [history, node]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") { e.preventDefault(); onClose(); return; }
      if (e.key === "Enter" && !e.shiftKey) {
        const el = e.target as HTMLElement;
        const typing = el && (el.tagName === "TEXTAREA" || el.tagName === "INPUT" || (el as any).isContentEditable);
        if (!typing) { e.preventDefault(); onClose(); }
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const go = (label: string, nextId: string) => {
    const n = NODES[nextId];
    if (!n) return;
    setHistory((h) => [...h, { from: "user", text: label }, { from: "coach", text: n.say, card: n.card, note: n.note }]);
    setNode(n);
  };

  const onSend = () => {
    const t = text.trim(); if (!t) return;
    setText("");
    if (node && node.route) go(t, node.route);
    else if (node && node.optsMap) { const key = Object.keys(node.optsMap)[0]; go(t, node.optsMap[key]); }
    else setHistory((h) => [...h, { from: "user", text: t }, { from: "coach", text: "Got it — noted. Tap one of the suggestions and I’ll take it from there." }]);
  };

  const meta = MODE_META[mode] || MODE_META.ask;

  return (
    <div className="sx-backdrop" onClick={onClose}>
      <div className="sx-panel" onClick={(e) => e.stopPropagation()}>
        <div className="sx-head">
          <img className="sx-mascot bg-bob" src="/togi-mascot.png" alt="Togi" />
          <div className="sx-head-txt"><div className="sx-head-label">{meta.label}</div><div className="sx-head-sub">{meta.sub}</div></div>
          <span className="sx-live"><span className="sx-live-dot" /> live</span>
          <button className="icon-btn" onClick={onClose}><IcClose size={15} /></button>
        </div>

        <div className="sx-body" ref={scroller}>
          {history.map((m, i) => (
            <div key={i} className="sx-turn">
              <MessageBubble from={m.from}>{m.text}</MessageBubble>
              {m.card && <div className="sx-attach">{renderCard(m.card)}</div>}
              {m.note && <div className="sx-note">{m.note}</div>}
            </div>
          ))}
        </div>

        <div className="sx-foot">
          {node && node.openers && (
            <div className="sx-openers">
              {node.openers.map((o: string) => (
                <button key={o} className="sx-opener" onClick={() => go(o, node.optsMap[o])}>{o} <IcArrowUp size={12} /></button>
              ))}
            </div>
          )}
          {node && node.opts && (
            <div className="sx-replies">
              {node.opts.map(([label, next]: any) => (<button key={label} className="sx-reply" onClick={() => go(label, next)}>{label}</button>))}
            </div>
          )}
          {node && node.done && (
            <button className="sx-done" onClick={() => onAction(node.done.action)}>{node.done.label} <IcArrow size={15} /></button>
          )}
          {node && (node.input || node.openers || node.route) && (
            <div className="sx-composer"><Composer value={text} onChange={setText} onSend={onSend} placeholder="speak, or type to Togi…" /></div>
          )}
          {node && node.opts && (<div className="sx-mic-hint"><IcMic size={13} /> Speak your answer, or tap above</div>)}
        </div>
      </div>
    </div>
  );
}
