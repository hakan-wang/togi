/* ============================================================
   Togi — behavioral insight MEMORY (per togi_insights_spec.md §6, §9).
   Small living notes, separate from the raw archive. Local for now (per-browser);
   a Supabase `insights` table can back this later. Code owns the lifecycle:
   candidate → active → fading → retired, and the surfaced cap.
   ============================================================ */
import { Stats } from "./behavior";

export interface InsightRecord {
  id: string;
  family: string;
  statement: string;
  metric?: string;
  suggestion?: string;
  confidence: number;
  evidence_count: number;
  status: "candidate" | "active" | "fading" | "retired";
  applied?: boolean; // user pressed "Apply to planning" → Togi leans on it harder when planning
  first_seen: string;
  last_confirmed: string;
}

const LS = "togi.insights.v1";
const SURFACE_CAP = 5;

function load(): InsightRecord[] {
  if (typeof window === "undefined") return [];
  try { return JSON.parse(window.localStorage.getItem(LS) || "[]"); } catch { return []; }
}
function save(rows: InsightRecord[]) {
  if (typeof window === "undefined") return;
  try { window.localStorage.setItem(LS, JSON.stringify(rows)); } catch { /* ignore */ }
}

export function loadMemory(): InsightRecord[] { return load(); }
/** Insights to actually show: active, strongest first, capped. */
export function surfaced(rows: InsightRecord[]): InsightRecord[] {
  const active = rows.filter((r) => r.status === "active").sort((a, b) => b.confidence - a.confidence);
  if (active.length > SURFACE_CAP) console.warn(`insights: showing ${SURFACE_CAP} of ${active.length} active (capped)`);
  return active.slice(0, SURFACE_CAP);
}

export function dismiss(id: string): InsightRecord[] {
  const rows = load().map((r) => (r.id === id ? { ...r, status: "retired" as const } : r));
  save(rows); return rows;
}

/** User confirms this insight should steer planning → keep it active + flag it applied. */
export function applyToPlanning(id: string): InsightRecord[] {
  const rows = load().map((r) => (r.id === id ? { ...r, applied: true, status: "active" as const, confidence: Math.max(r.confidence, 0.8) } : r));
  save(rows); return rows;
}

const STOP = new Set(["your", "you", "the", "and", "that", "with", "into", "from", "this", "have", "after", "before", "than", "they", "them", "what", "when", "where", "min", "day", "days"]);
function tokens(s: string): Set<string> { const ws: string[] = s.toLowerCase().match(/[a-z]+/g) || []; return new Set(ws.filter((w) => w.length > 3 && !STOP.has(w))); }
function overlap(a: string, b: string): number {
  const A = tokens(a), B = tokens(b); if (!A.size || !B.size) return 0;
  let inter = 0; A.forEach((w) => { if (B.has(w)) inter++; });
  return inter / Math.min(A.size, B.size);
}

/** Merge a fresh AI pass into memory, applying the lifecycle. Returns + persists. */
export function reconcile(incoming: any[], nowISO: string): InsightRecord[] {
  let rows = load();
  const byId = (id: string) => rows.find((r) => r.id === id);

  for (const inc of incoming) {
    const rec = (inc.reconcile || "new").toString();
    if (rec.startsWith("confirms:")) {
      const t = byId(rec.split(":")[1]); if (t) { t.evidence_count = Math.max(t.evidence_count, inc.evidence_count || t.evidence_count) + 1; t.confidence = Math.min(1, t.confidence + 0.1); t.status = t.confidence >= 0.6 ? "active" : "candidate"; t.last_confirmed = nowISO; if (inc.statement) t.statement = inc.statement; continue; }
    }
    if (rec.startsWith("contradicts:")) {
      const t = byId(rec.split(":")[1]); if (t) { t.confidence = Math.max(0, t.confidence - 0.3); t.status = t.confidence < 0.3 ? "retired" : "fading"; t.last_confirmed = nowISO; continue; }
    }
    // "new" — but dedupe against an existing non-retired note in the same family
    const match = rows.find((r) => r.status !== "retired" && r.family === inc.family && overlap(r.statement, inc.statement || "") >= 0.5);
    if (match) {
      match.evidence_count += 1; match.confidence = Math.min(1, Math.max(match.confidence, inc.confidence || 0) + 0.05);
      match.status = match.confidence >= 0.6 ? "active" : "candidate"; match.last_confirmed = nowISO; match.statement = inc.statement || match.statement; if (inc.suggestion) match.suggestion = inc.suggestion;
      continue;
    }
    const conf = typeof inc.confidence === "number" ? inc.confidence : 0.7;
    rows.push({
      id: `ins-${rows.length}-${nowISO.slice(0, 10)}-${Math.round(conf * 100)}`,
      family: inc.family, statement: inc.statement, metric: inc.metric || undefined, suggestion: inc.suggestion || undefined,
      confidence: conf, evidence_count: inc.evidence_count || 3,
      status: conf >= 0.6 ? "active" : "candidate", first_seen: nowISO, last_confirmed: nowISO,
    });
  }
  save(rows); return rows;
}

/** Run the full refresh: compute stats client-side, ask the AI, reconcile into memory. */
export async function refreshInsights(stats: Stats, nowISO: string): Promise<InsightRecord[]> {
  const memory = load();
  try {
    const res = await fetch("/api/insights", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ stats, memory }) });
    const data = await res.json();
    if (Array.isArray(data.insights) && data.insights.length) return reconcile(data.insights, nowISO);
  } catch (e) { console.warn("refreshInsights failed:", e); }
  return memory;
}
