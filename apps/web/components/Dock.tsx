/* ============================================================
   Togi — variant B: compact persistent companion dock (ported).
   Axolotl + status line + tap-to-talk. Status: idle / waiting-on-you / ack.
   ============================================================ */
"use client";
import * as React from "react";
import { useEffect, useRef, useState } from "react";
import { COACH_ACK, INSIGHT } from "../lib/data";
import { IcArrow, IcCheck, IcChevron, IcMic, IcPlan, IcReturn, IcSpark, IcTrash, IcWave } from "./icons";

function DockInsight({ onOpenSession }: any) {
  const i = INSIGHT;
  return (
    <div className="reveal-panel">
      <p className="insight-text">{i.text}</p>
      <button className="insight-nudge" onClick={() => onOpenSession("plan")}>{i.nudge} <IcArrow size={14} /></button>
    </div>
  );
}

export function TogiDock({ onOpenSession, coach }: any) {
  const [open, setOpen] = useState(false);
  const [panel, setPanel] = useState<string | null>(null);
  const ref = useRef<HTMLDivElement>(null);
  const toggle = (p: string) => setPanel((cur) => (cur === p ? null : p));

  const state = (coach && coach.state) || "idle";
  const waiting = state === "pending";
  const ack = state === "ack";
  const statusText = ack ? (coach.msg || COACH_ACK) : waiting ? "waiting on you" : "here, and listening";

  useEffect(() => {
    const h = (e: PointerEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) { setOpen(false); setPanel(null); } };
    window.addEventListener("pointerdown", h);
    return () => window.removeEventListener("pointerdown", h);
  }, []);

  return (
    <div className={"togi-dock" + (open ? " open" : "") + (waiting ? " waiting" : "") + (ack ? " ack" : "")} ref={ref}>
      {open && (
        <div className="dock-pop">
          <div className="dock-pop-head">
            <span className="dock-pop-name serif">Togi</span>
            <span className="persona-status"><span className="persona-live-dot" /> {statusText}</span>
          </div>
          <button className="ask-togi" onClick={() => onOpenSession("ask")}>
            <span className="ask-togi-l"><IcMic size={16} /> Ask Togi</span>
            <span className="kbd">⌘K</span>
          </button>
          <div className="togi-actions">
            <button onClick={() => onOpenSession("self")}><IcWave size={16} /> Self check-in</button>
            <button onClick={() => onOpenSession("plan")}><IcPlan size={16} /> Plan</button>
          </div>
          <div className="togi-reveals">
            <button className={"reveal-tab" + (panel === "insight" ? " on" : "")} onClick={() => toggle("insight")}>
              <span className="reveal-badge spark"><IcSpark size={13} /></span>
              <span className="reveal-label">Togi noticed</span>
              <span className="reveal-count">1</span>
              <IcChevron className="reveal-chev" size={15} />
            </button>
            {panel === "insight" && <DockInsight onOpenSession={onOpenSession} />}
          </div>
        </div>
      )}

      <button className="dock-bar" onClick={() => setOpen((v) => !v)} title="Talk to Togi">
        <span className="dock-orb"><span className="dock-pulse" /><img className="dock-mascot bg-bob" src="/togi-mascot.png" alt="Togi" /></span>
        <span className="dock-bar-txt">
          <span className="dock-bar-name">Togi</span>
          <span className="dock-bar-sub">{!ack && <span className="persona-live-dot" />}{statusText}</span>
        </span>
        <span className="dock-mic"><IcMic size={17} /></span>
      </button>
    </div>
  );
}
