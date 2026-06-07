/* ============================================================
   Togi — Google Calendar event editor (create / edit / delete).
   Edits write straight back to the user's real Google Calendar via /api/google/events.
   Times are edited in the browser's local timezone and serialized to ISO.
   ============================================================ */
"use client";
import * as React from "react";
import { useState } from "react";
import { PlanBlock } from "../lib/data";
import { IcCheck, IcClose, IcTrash } from "./icons";

export interface EventDraft { title: string; startISO: string; endISO: string; note?: string; }

// "HH:MM" (local) on a given base date → ISO string
function toISO(base: Date, hhmm: string): string {
  const [h, m] = hhmm.split(":").map(Number);
  const d = new Date(base);
  d.setHours(h || 0, m || 0, 0, 0);
  return d.toISOString();
}
// ISO → "HH:MM" (local) for an <input type="time">
function toHHMM(iso?: string): string {
  const d = iso ? new Date(iso) : new Date();
  return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

export function GcalEventEditor({ block, onSave, onDelete, onClose }: {
  block: PlanBlock | null;                       // null → creating a new event
  onSave: (draft: EventDraft, gcalId?: string) => Promise<void>;
  onDelete: (gcalId: string) => Promise<void>;
  onClose: () => void;
}) {
  const editing = !!block?.gcalId;
  const baseDate = block?.startISO ? new Date(block.startISO) : new Date();
  const [title, setTitle] = useState(block?.title || "");
  const [start, setStart] = useState(toHHMM(block?.startISO));
  const [end, setEnd] = useState(block?.startISO ? toHHMM(block?.endISO) : toHHMM(new Date(Date.now() + 60 * 60 * 1000).toISOString()));
  const [note, setNote] = useState(block?.note || "");
  const [busy, setBusy] = useState<"" | "save" | "delete">("");
  const [err, setErr] = useState<string | null>(null);

  async function save() {
    setErr(null);
    if (!title.trim()) return setErr("Give the event a title.");
    if (end <= start) return setErr("End time must be after the start.");
    setBusy("save");
    try {
      await onSave({ title: title.trim(), startISO: toISO(baseDate, start), endISO: toISO(baseDate, end), note: note.trim() || undefined }, block?.gcalId);
      onClose();
    } catch (e: any) { setErr(e?.message || "Couldn’t save to Google Calendar."); setBusy(""); }
  }
  async function remove() {
    if (!block?.gcalId) return;
    setErr(null); setBusy("delete");
    try { await onDelete(block.gcalId); onClose(); }
    catch (e: any) { setErr(e?.message || "Couldn’t delete from Google Calendar."); setBusy(""); }
  }

  const field: React.CSSProperties = { width: "100%", padding: "9px 11px", borderRadius: 10, border: "1px solid var(--line, #e3e3e6)", background: "var(--surface, #fff)", color: "inherit", font: "inherit" };
  const label: React.CSSProperties = { fontSize: 12, opacity: 0.7, marginBottom: 5, display: "block" };

  return (
    <div className="gcal-edit-overlay" style={{ position: "fixed", inset: 0, zIndex: 60, display: "grid", placeItems: "center", background: "rgba(20,20,24,0.34)" }} onClick={onClose}>
      <div className="card" style={{ width: "min(440px, 92vw)", padding: 20 }} onClick={(e) => e.stopPropagation()}>
        <div className="card-head" style={{ marginBottom: 14 }}>
          <span className="card-title">{editing ? "Edit event" : "New event"}</span>
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
            <label style={label}>Note / location <span style={{ opacity: 0.5 }}>(optional)</span></label>
            <input style={field} value={note} onChange={(e) => setNote(e.target.value)} placeholder="" />
          </div>
          {editing && <div style={{ fontSize: 12, opacity: 0.55 }}>{new Date(baseDate).toLocaleDateString(undefined, { weekday: "long", month: "short", day: "numeric" })} · syncs to your Google Calendar</div>}
          {err && <div style={{ fontSize: 13, color: "var(--danger, #d8443c)" }}>{err}</div>}
        </div>

        <div style={{ display: "flex", gap: 10, marginTop: 18, alignItems: "center" }}>
          {editing && (
            <button className="btn-ghost" style={{ color: "var(--danger, #d8443c)" }} onClick={remove} disabled={!!busy}>
              <IcTrash size={14} /> {busy === "delete" ? "Deleting…" : "Delete"}
            </button>
          )}
          <div style={{ flex: 1 }} />
          <button className="btn-ghost" onClick={onClose} disabled={!!busy}>Cancel</button>
          <button className="cta-btn" onClick={save} disabled={!!busy}>
            <IcCheck size={14} /> {busy === "save" ? "Saving…" : editing ? "Save" : "Add"}
          </button>
        </div>
      </div>
    </div>
  );
}
