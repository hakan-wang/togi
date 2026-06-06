/* ============================================================
   Togi — persistence for Real entries + the project/activity vocabulary.
   Primary: Supabase (per-user, RLS). Fallback: localStorage so it always works.

   Supabase schema lives in CONNECTING.md (real_entries + projects + activities).
   ============================================================ */
import { Domain, PlanBlock, RealEntry, STARTER_ACTIVITIES } from "./data";
import { ensureSession } from "./supabase";

const LS_ENTRIES = "togi.real_entries.v2";
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
export async function saveRealEntry(row: StoredEntry): Promise<{ ok: boolean; via: "supabase" | "local" }> {
  lsSet(LS_ENTRIES, [...lsGet<StoredEntry[]>(LS_ENTRIES, []), row]); // mirror locally first

  const sb = await ensureSession();
  if (sb) {
    try {
      const { data: { user } } = await sb.auth.getUser();
      if (user) {
        const { id, ...insertable } = row; // let Postgres generate the uuid
        const { error } = await sb.from("real_entries").insert({ ...insertable, user_id: user.id });
        if (!error) return { ok: true, via: "supabase" };
        console.warn("supabase insert failed, kept local:", error.message);
      }
    } catch (e) { console.warn("supabase unavailable, kept local:", e); }
  }
  return { ok: true, via: "local" };
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
  return {
    id: row.id || `live-${index}`,
    slot: row.matched_plan_id || undefined,
    off: !row.matched_plan_id,
    match: !!row.matched,
    domain: row.domain as Domain,
    project: row.project || null,
    activity: row.activity,
    title: row.title,
    note: row.note || null,
    confidence: row.confidence ?? undefined,
    live: true,
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
const LS_PLAN = "togi.plan.v1";
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
