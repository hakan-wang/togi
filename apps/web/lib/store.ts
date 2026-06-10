/* ============================================================
   Togi — persistence for Real entries + the project/activity vocabulary.
   Primary: Supabase (per-user, RLS). Fallback: localStorage so it always works.

   Supabase schema lives in CONNECTING.md (real_entries + projects + activities).
   ============================================================ */
import { Domain, PlanBlock, RealEntry, STARTER_ACTIVITIES } from "./data";
import { dayKey, isoFromDayMin } from "./dates";
import { ensureSession } from "./supabase";

const LS_ENTRIES = "togi.real_entries.v3";
const LS_ACTIVITIES = "togi.activities.v1";
const LS_PROJECTS = "togi.projects.v1";

export interface StoredEntry {
  id?: string;
  title: string;
  domain: string;
  project?: string | null;
  activity: string;
  note?: string | null;
  duration_min?: number | null;
  matched_plan_id?: string | null;
  matched?: boolean;
  confidence?: number | null;
  transcript?: string | null;
  started_at?: string | null;
  created_at?: string;
}

/* ---------- local helpers ---------- */
function lsGet<T>(k: string, fallback: T): T {
  if (typeof window === "undefined") return fallback;
  try { return JSON.parse(window.localStorage.getItem(k) || "null") ?? fallback; } catch { return fallback; }
}
function lsSet(k: string, v: any) {
  if (typeof window === "undefined") return;
  try { window.localStorage.setItem(k, JSON.stringify(v)); } catch { /* ignore */ }
}

/* ---------- Real entries ---------- */
const isUuid = (s?: string | null) => !!s && /^[0-9a-f]{8}-[0-9a-f]{4}-/i.test(s);
/** A stored row matches a UI entry by id, else by title + start time (good enough to edit/delete). */
function sameRow(r: StoredEntry, t: { id?: string; title?: string; started_at?: string | null }): boolean {
  if (t.id && r.id && r.id === t.id) return true;
  return r.title === t.title && (r.started_at ?? null) === (t.started_at ?? null);
}

export async function saveRealEntry(row: StoredEntry): Promise<{ ok: boolean; via: "supabase" | "local"; id: string }> {
  const clientId = row.id || `loc-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
  lsSet(LS_ENTRIES, [...lsGet<StoredEntry[]>(LS_ENTRIES, []), { ...row, id: clientId }]); // offline-first mirror

  const sb = await ensureSession();
  if (sb) {
    try {
      const { data: { user } } = await sb.auth.getUser();
      if (user) {
        const { id, ...insertable } = row; // let Postgres generate the uuid
        const { data, error } = await sb.from("real_entries").insert({ ...insertable, user_id: user.id }).select("id").single();
        if (!error && data) {
          const dbId = (data as any).id as string;
          // upgrade the local mirror's id to the real DB id so later edits/deletes match cleanly
          lsSet(LS_ENTRIES, lsGet<StoredEntry[]>(LS_ENTRIES, []).map((r) => (r.id === clientId ? { ...r, id: dbId } : r)));
          return { ok: true, via: "supabase", id: dbId };
        }
        if (error) console.warn("supabase insert failed, kept local:", error.message);
      }
    } catch (e) { console.warn("supabase unavailable, kept local:", e); }
  }
  return { ok: true, via: "local", id: clientId };
}

/** Remove one Real entry (local mirror + cloud, best-effort). */
export async function deleteRealEntry(target: { id?: string; title?: string; started_at?: string | null }): Promise<void> {
  lsSet(LS_ENTRIES, lsGet<StoredEntry[]>(LS_ENTRIES, []).filter((r) => !sameRow(r, target)));
  const sb = await ensureSession();
  if (sb) {
    try {
      const { data: { user } } = await sb.auth.getUser();
      if (user) {
        let q = sb.from("real_entries").delete().eq("user_id", user.id);
        if (isUuid(target.id)) q = q.eq("id", target.id!);
        else if (target.title != null) { q = q.eq("title", target.title); q = target.started_at ? q.eq("started_at", target.started_at) : q.is("started_at", null); }
        else return;
        await q;
      }
    } catch (e) { console.warn("deleteRealEntry: cloud skip:", e); }
  }
}

/** Patch one Real entry (reschedule and/or rename). Local mirror + cloud, best-effort. */
export async function patchRealEntry(target: { id?: string; title?: string; started_at?: string | null }, patch: Partial<StoredEntry>): Promise<void> {
  lsSet(LS_ENTRIES, lsGet<StoredEntry[]>(LS_ENTRIES, []).map((r) => (sameRow(r, target) ? { ...r, ...patch } : r)));
  const sb = await ensureSession();
  if (sb) {
    try {
      const { data: { user } } = await sb.auth.getUser();
      if (user) {
        let q = sb.from("real_entries").update(patch).eq("user_id", user.id);
        if (isUuid(target.id)) q = q.eq("id", target.id!);
        else if (target.title != null) { q = q.eq("title", target.title); q = target.started_at ? q.eq("started_at", target.started_at) : q.is("started_at", null); }
        else return;
        await q;
      }
    } catch (e) { console.warn("patchRealEntry: cloud skip:", e); }
  }
}

/** Wipe the Real check-ins logged TODAY (local mirror + cloud) so testing starts clean.
   Plans are untouched. Slotted entries have no started_at — they count as today by design. */
export async function clearTodayRealEntries(): Promise<number> {
  const today = dayKey();
  const isToday = (r: StoredEntry) => (r.started_at ? dayKey(new Date(r.started_at)) : today) === today;

  const all = lsGet<StoredEntry[]>(LS_ENTRIES, []);
  const removed = all.filter(isToday).length;
  lsSet(LS_ENTRIES, all.filter((r) => !isToday(r)));

  const sb = await ensureSession();
  if (sb) {
    try {
      const { data: { user } } = await sb.auth.getUser();
      if (user) {
        const start = isoFromDayMin(today, 0);
        const end = isoFromDayMin(today, 24 * 60);
        await sb.from("real_entries").delete().eq("user_id", user.id).gte("started_at", start).lt("started_at", end);
        await sb.from("real_entries").delete().eq("user_id", user.id).is("started_at", null);
      }
    } catch (e) { console.warn("clearTodayRealEntries: cloud delete skipped:", e); }
  }
  return removed;
}

export async function loadRealEntries(): Promise<StoredEntry[]> {
  const sb = await ensureSession();
  if (sb) {
    try {
      const { data: { user } } = await sb.auth.getUser();
      if (user) {
        const { data, error } = await sb.from("real_entries").select("*").order("created_at", { ascending: true });
        if (!error && data) return data as StoredEntry[];
      }
    } catch { /* fall through */ }
  }
  return lsGet<StoredEntry[]>(LS_ENTRIES, []);
}

export function toRealEntry(row: StoredEntry, index: number): RealEntry {
  const slot = row.matched_plan_id || undefined;
  let start: number | undefined, end: number | undefined, date: string | undefined;
  if (row.started_at) {
    const d = new Date(row.started_at);
    date = dayKey(d);
    if (!slot) { start = d.getHours() * 60 + d.getMinutes(); end = start + (row.duration_min || 45); }
  }
  return {
    id: row.id || `live-${index}`,
    slot, off: !slot, match: !!row.matched,
    domain: row.domain as Domain, project: row.project || null, activity: row.activity,
    title: row.title, note: row.note || null, confidence: row.confidence ?? undefined,
    start, end, date, live: true,
  };
}

/* ---------- Vocabulary (projects + activities) ---------- */
export interface Vocabulary { projects: string[]; activities: string[]; }

export async function loadVocabulary(): Promise<Vocabulary> {
  const localActs = lsGet<string[]>(LS_ACTIVITIES, STARTER_ACTIVITIES);
  const localProjs = lsGet<string[]>(LS_PROJECTS, []);
  const sb = await ensureSession();
  if (sb) {
    try {
      const { data: { user } } = await sb.auth.getUser();
      if (user) {
        let { data: acts } = await sb.from("activities").select("name");
        if (!acts || acts.length === 0) {
          // seed the starter vocabulary for this user, once
          await sb.from("activities").upsert(STARTER_ACTIVITIES.map((name) => ({ name, user_id: user.id })), { onConflict: "user_id,name", ignoreDuplicates: true });
          acts = STARTER_ACTIVITIES.map((name) => ({ name }));
        }
        const { data: projs } = await sb.from("projects").select("name");
        const vocab = { projects: (projs || []).map((p: any) => p.name), activities: (acts || []).map((a: any) => a.name) };
        lsSet(LS_ACTIVITIES, vocab.activities); lsSet(LS_PROJECTS, vocab.projects);
        return vocab;
      }
    } catch { /* fall through to local */ }
  }
  return { projects: localProjs, activities: localActs };
}

export async function addActivity(name: string) {
  if (!name) return;
  const acts = lsGet<string[]>(LS_ACTIVITIES, STARTER_ACTIVITIES);
  if (!acts.some((a) => a.toLowerCase() === name.toLowerCase())) lsSet(LS_ACTIVITIES, [...acts, name]);
  const sb = await ensureSession();
  if (sb) {
    try { const { data: { user } } = await sb.auth.getUser(); if (user) await sb.from("activities").upsert({ name, user_id: user.id }, { onConflict: "user_id,name", ignoreDuplicates: true }); } catch { /* ignore */ }
  }
}

/* ---------- Planned blocks (added during planning; local for now) ---------- */
const LS_PLAN = "togi.plan.v2";
export function loadPlanLocal(): PlanBlock[] { return lsGet<PlanBlock[]>(LS_PLAN, []); }
export function savePlanLocal(blocks: PlanBlock[]) { lsSet(LS_PLAN, blocks); }

export async function addProject(name: string) {
  if (!name) return;
  const projs = lsGet<string[]>(LS_PROJECTS, []);
  if (!projs.some((p) => p.toLowerCase() === name.toLowerCase())) lsSet(LS_PROJECTS, [...projs, name]);
  const sb = await ensureSession();
  if (sb) {
    try { const { data: { user } } = await sb.auth.getUser(); if (user) await sb.from("projects").upsert({ name, user_id: user.id }, { onConflict: "user_id,name", ignoreDuplicates: true }); } catch { /* ignore */ }
  }
}
