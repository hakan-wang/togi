/* ============================================================
   Togi — general event editor for non-Google events (local plan blocks + real
   check-ins). Works in minutes-from-midnight (the app's native unit). Google
   Calendar events use GcalEventEditor instead (it writes back to Google).
   ============================================================ */
"use client";
import * as React from "react";
import { useState } from "react";
import { Domain, DOMAINS, domainShort } from "../lib/data";
import { IcCheck, IcClose, IcTrash } from "./icons";

export interface EditableEvent {
  kind: "plan" | "real";
  id: string;
  title: string;
  start: number;       // minutes from midnight
  end: number;
  note?: string | null;
  project?: string | null;
  domain: Domain;
}
export interface EventChanges { title: string; start: number; end: number; note: string | null; }

const hhmm = (m: number) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
const mins = (s: string) => { const [h, m] = s.split(":").map(Number); return (h || 0) * 60 + (m || 0); };

export function EventEditor({ event, onSave, onDelete, onClose }: {
  event: EditableEvent;
  onSave: (changes: EventChanges) => Promise<void> | void;
  onDelete: () => Promise<void> | void;
  onClose: () => void;
}) {
  const C = DOMAINS[event.domain];
  const [title, setTitle] = useState(event.title || "");
  const [start, setStart] = useState(hhmm(event.start));
  const [end, setEnd] = useState(hhmm(event.end));
  const [note, setNote] = useState(event.note || "");
  const [busy, setBusy] = useState<"" | "save" | "delete">("");
  const [err, setErr] = useState<string | null>(null);

  async function save() {
    setErr(null);
    if (!title.trim()) return setErr("Give it a title.");
    if (mins(end) <= mins(start)) return setErr("End time must be after the start.");
    setBusy("save");
    try { await onSave({ title: title.trim(), start: mins(start), end: mins(end), note: note.trim() || null }); onClose(); }
    catch (e: any) { setErr(e?.message || "Couldn’t save."); setBusy(""); }
  }
  async function remove() {
    setErr(null); setBusy("delete");
    try { await onDelete(); onClose(); }
    catch (e: any) { setErr(e?.message || "Couldn’t delete."); setBusy(""); }
  }

  const field: React.CSSProperties = { width: "100%", padding: "9px 11px", borderRadius: 10, border: "1px solid var(--togi-line-2, #e3e3e6)", background: "var(--surface, #fff)", color: "inherit", font: "inherit" };
  const label: React.CSSProperties = { fontSize: 12, opacity: 0.7, marginBottom: 5, display: "block" };

  return (
    <div className="gcal-edit-overlay" style={{ position: "fixed", inset: 0, zIndex: 60, display: "grid", placeItems: "center", background: "rgba(20,20,24,0.34)" }} onClick={onClose}>
      <div className="card" style={{ width: "min(440px, 92vw)", padding: 20 }} onClick={(e) => e.stopPropagation()}>
        <div className="card-head" style={{ marginBottom: 14 }}>
          <span className="card-title"><span className="cat-swatch" style={{ background: C.color, marginRight: 8 }} />{event.kind === "real" ? "Edit check-in" : "Edit event"}</span>
          <button className="btn-ghost" style={{ padding: 6 }} onClick={onClose} title="Close"><IcClose size={15} /></button>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 13 }}>
          <div>
            <label style={label}>Title</label>
            <input style={field} value={title} onChange={(e) => setTitle(e.target.value)} placeholder="e.g. Edit launch vlog" autoFocus />
          </div>
          <div style={{ display: "flex", gap: 12 }}>
            <div style={{ flex: 1 }}><label style={label}>Start</label><input type="time" style={field} value={start} onChange={(e) => setStart(e.target.value)} /></div>
            <div style={{ flex: 1 }}><label style={label}>End</label><input type="time" style={field} value={end} onChange={(e) => setEnd(e.target.value)} /></div>
          </div>
          <div>
            <label style={label}>Note <span style={{ opacity: 0.5 }}>(optional)</span></label>
            <input style={field} value={note} onChange={(e) => setNote(e.target.value)} placeholder="" />
          </div>
          <div style={{ fontSize: 12, opacity: 0.55 }}>{domainShort(event.domain)}{event.project ? ` · ${event.project}` : ""}</div>
          {err && <div style={{ fontSize: 13, color: "var(--danger, #d8443c)" }}>{err}</div>}
        </div>

        <div style={{ display: "flex", gap: 10, marginTop: 18, alignItems: "center" }}>
          <button className="btn-ghost" style={{ color: "var(--danger, #d8443c)" }} onClick={remove} disabled={!!busy}>
            <IcTrash size={14} /> {busy === "delete" ? "Deleting…" : "Delete"}
          </button>
          <div style={{ flex: 1 }} />
          <button className="btn-ghost" onClick={onClose} disabled={!!busy}>Cancel</button>
          <button className="cta-btn" onClick={save} disabled={!!busy}><IcCheck size={14} /> {busy === "save" ? "Saving…" : "Save"}</button>
        </div>
      </div>
    </div>
  );
}
