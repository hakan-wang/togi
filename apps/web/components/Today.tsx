/* ============================================================
   Togi — Today view pieces (variant B), wired for the real vertical slice.
   • TodayCheckin — collapsed notification by default (mic OFF). A single tap
     expands it AND starts the mic (the only moment it goes live). Live waveform,
     pause/resume, Esc cancels, "type instead" fallback, Enter submits.
   • InsightBanner — one slim live short-term pattern above the calendar.
   ============================================================ */
"use client";
import * as React from "react";
import { useEffect, useState } from "react";
import { CATEGORIES, JUST_ENDED } from "../lib/data";
import { BannerInsight } from "../lib/insights";
import { useRecorder } from "../lib/useRecorder";
import { IcChat, IcClose, IcMic, IcPause, IcPlay, IcSpark, IcArrow } from "./icons";
import { Composer } from "./ds";

function LiveWave({ n = 28, level = 0 }: { n?: number; level?: number }) {
  const bars = [];
  for (let i = 0; i < n; i++) {
    bars.push(<i key={i} style={{ animationDelay: (i % 7) * 0.09 + "s", animationDuration: 0.7 + (i % 5) * 0.12 + "s" }} />);
  }
  return <span className="live-wave" aria-hidden="true" style={{ transform: `scaleY(${0.6 + level * 0.9})` }}>{bars}</span>;
}

export function TodayCheckin({ onSubmit }: { onSubmit: (input: { blob?: Blob | null; text?: string }) => Promise<void> }) {
  const J = JUST_ENDED;
  const C = CATEGORIES[J.cat];
  const rec = useRecorder();
  const [mode, setMode] = useState<"collapsed" | "voice" | "type">("collapsed");
  const [busy, setBusy] = useState(false);
  const [text, setText] = useState("");
  const [err, setErr] = useState<string | null>(null);

  const collapse = () => { setMode("collapsed"); setBusy(false); setText(""); setErr(null); };

  // start voice: the ONLY place the mic opens
  const startVoice = async () => {
    setErr(null); setMode("voice");
    try { await rec.start(); } catch { setMode("type"); /* fall back to typing if mic denied */ }
  };

  const cancelVoice = () => { rec.cancel(); collapse(); };

  const submitVoice = async () => {
    setBusy(true);
    const blob = await rec.stop();
    try { await onSubmit({ blob }); collapse(); }
    catch (e: any) { setErr(e?.message || "Something went wrong."); setBusy(false); }
  };

  const submitText = async () => {
    const t = text.trim(); if (!t) return;
    setBusy(true);
    try { await onSubmit({ text: t }); collapse(); }
    catch (e: any) { setErr(e?.message || "Something went wrong."); setBusy(false); }
  };

  // keyboard only while expanded: Esc cancels, Enter submits voice (not while typing)
  useEffect(() => {
    if (mode === "collapsed") return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") { e.preventDefault(); mode === "voice" ? cancelVoice() : collapse(); }
      else if (e.key === "Enter" && !e.shiftKey && mode === "voice" && !busy) {
        const el = e.target as HTMLElement;
        const typing = el && (el.tagName === "TEXTAREA" || el.tagName === "INPUT" || (el as any).isContentEditable);
        if (!typing) { e.preventDefault(); submitVoice(); }
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [mode, busy]); // eslint-disable-line react-hooks/exhaustive-deps

  // ---- collapsed: calm notification pill (tap to start the check-in) ----
  if (mode === "collapsed") {
    return (
      <button className="checkin-pill" onClick={startVoice} title="Tap to check in (starts the mic)">
        <span className="checkin-pill-orb"><img className="checkin-pill-mascot bg-bob" src="/togi-mascot.png" alt="Togi" /></span>
        <span className="checkin-pill-text"><strong>{J.block}</strong> just ended — check in</span>
        <span className="checkin-pill-mins num"><span className="cat-swatch" style={{ background: C.color }} />{J.mins} min</span>
        <span className="checkin-pill-go"><IcMic size={15} /></span>
      </button>
    );
  }

  const listening = !rec.isPaused;
  return (
    <div className="checkin-card" role="dialog" aria-label="Check-in">
      <span className="checkin-accent" style={{ background: C.color }} />
      <span className="checkin-orb"><img className="checkin-mascot bg-bob" src="/togi-mascot.png" alt="Togi" /></span>

      <div className="checkin-main">
        <div className="checkin-status">
          {busy
            ? <span className="checkin-live"><span className="checkin-live-dot" /> Sorting that…</span>
            : mode === "type"
              ? <span className="checkin-live paused"><IcChat size={12} /> Type instead</span>
              : listening
                ? <span className="checkin-live"><span className="checkin-live-dot" /> Listening</span>
                : <span className="checkin-live paused"><IcPause size={12} /> Paused</span>}
          <span className="checkin-chip"><span className="cat-swatch" style={{ background: C.color }} />{C.label}</span>
        </div>
        <div className="checkin-title"><strong>{J.block}</strong> just ended — tell me what really happened.</div>
        <div className="checkin-sub num">
          {J.window} · {busy ? "Togi is categorizing…" : mode === "type" ? "type your check-in, Enter to send" : listening ? "just talk, I’m listening" : "paused — resume when ready"}
        </div>
        {err && <div className="checkin-sub" style={{ color: "var(--alert)" }}>{err}</div>}
        {mode === "voice" && !busy && <span className={"live-wave-wrap" + (rec.isPaused ? " is-paused" : "")}><LiveWave level={rec.level} /></span>}
        {mode === "type" && !busy && (
          <div style={{ marginTop: 8 }}>
            <Composer value={text} onChange={setText} onSend={submitText} placeholder="e.g. I scrolled TikTok for about 40 minutes instead of editing" />
          </div>
        )}
      </div>

      <div className="checkin-side">
        <div className="checkin-keys">
          <span><kbd>Enter</kbd> {mode === "type" ? "send" : "done"}</span>
          <span><kbd>Esc</kbd> cancel</span>
        </div>
        <div className="checkin-ctrls">
          {mode === "voice" && !busy && (
            <button className="checkin-ctrl" onClick={() => (rec.isPaused ? rec.resume() : rec.pause())} title={rec.isPaused ? "Resume" : "Pause"}>
              {rec.isPaused ? <IcPlay size={13} /> : <IcPause size={13} />} {rec.isPaused ? "Resume" : "Pause"}
            </button>
          )}
          {mode === "voice" && !busy && (
            <button className="checkin-ctrl" onClick={() => { rec.cancel(); setMode("type"); }}><IcChat size={13} /> type instead</button>
          )}
          {mode === "voice" && !busy && (
            <button className="checkin-ctrl" onClick={submitVoice} title="Submit (Enter)"><IcMic size={13} /> done</button>
          )}
          {mode === "type" && !busy && (
            <button className="checkin-ctrl" onClick={submitText} title="Send"><IcArrow size={13} /> send</button>
          )}
        </div>
      </div>

      <button className="checkin-x" title="Cancel (Esc)" onClick={mode === "voice" ? cancelVoice : collapse}><IcClose size={15} /></button>
    </div>
  );
}

export function InsightBanner({ data, onApply, onDismiss }: { data: BannerInsight; onApply: () => void; onDismiss: () => void }) {
  return (
    <div className="insight-banner">
      <span className="ib-badge"><IcSpark size={14} /></span>
      <span className="ib-label">Pattern</span>
      <span className="ib-divider" />
      <p className="ib-text">{data.text}</p>
      <button className="ib-apply" onClick={onApply}>Apply to planning <IcArrow size={14} /></button>
      <button className="ib-x" title="Dismiss" onClick={onDismiss}><IcClose size={13} /></button>
    </div>
  );
}
