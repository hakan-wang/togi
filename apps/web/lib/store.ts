/* ============================================================
   Togi — Real-entry persistence.
   Primary store: Supabase table `real_entries` (per-user, survives refresh).
   Fallback: browser localStorage, so the slice is always demoable before
   Supabase credentials are wired in.

   Supabase schema (apply in the SQL editor):
     create table real_entries (
       id uuid primary key default gen_random_uuid(),
       user_id uuid references auth.users on delete cascade,
       category text not null,
       sub_category text not null,
       description text not null,
       duration_min int,
       matched_plan_id text,
       matched boolean default false,
       transcript text,
       started_at timestamptz,
       created_at timestamptz default now()
     );
     alter table real_entries enable row level security;
     create policy "own rows" on real_entries
       for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
   ============================================================ */
import { RealEntry } from "./data";
import { getSupabase } from "./supabase";

const LS_KEY = "togi.real_entries.v1";

export interface StoredEntry {
  id: string;
  category: string;
  sub_category: string;
  description: string;
  duration_min?: number | null;
  matched_plan_id?: string | null;
  matched?: boolean;
  transcript?: string | null;
  started_at?: string | null;
  created_at?: string;
}

function readLocal(): StoredEntry[] {
  if (typeof window === "undefined") return [];
  try { return JSON.parse(window.localStorage.getItem(LS_KEY) || "[]"); } catch { return []; }
}
function writeLocal(rows: StoredEntry[]) {
  if (typeof window === "undefined") return;
  try { window.localStorage.setItem(LS_KEY, JSON.stringify(rows)); } catch { /* ignore */ }
}

/** Persist a single Real entry. Tries Supabase (if signed in), always mirrors to localStorage. */
export async function saveRealEntry(row: StoredEntry): Promise<{ ok: boolean; via: "supabase" | "local" }> {
  // mirror locally first so a refresh never loses the demo
  const local = readLocal();
  writeLocal([...local, row]);

  const sb = getSupabase();
  if (sb) {
    try {
      const { data: { user } } = await sb.auth.getUser();
      if (user) {
        const { error } = await sb.from("real_entries").insert({ ...row, user_id: user.id });
        if (!error) return { ok: true, via: "supabase" };
        console.warn("supabase insert failed, kept local:", error.message);
      }
    } catch (e) {
      console.warn("supabase unavailable, kept local:", e);
    }
  }
  return { ok: true, via: "local" };
}

/** Load persisted entries (Supabase if signed in, else localStorage). */
export async function loadRealEntries(): Promise<StoredEntry[]> {
  const sb = getSupabase();
  if (sb) {
    try {
      const { data: { user } } = await sb.auth.getUser();
      if (user) {
        const { data, error } = await sb.from("real_entries").select("*").order("created_at", { ascending: true });
        if (!error && data) return data as StoredEntry[];
      }
    } catch { /* fall through to local */ }
  }
  return readLocal();
}

/** Convert a persisted row into the in-memory RealEntry the calendar renders. */
export function toRealEntry(row: StoredEntry, index: number): RealEntry {
  return {
    id: row.id || `live-${index}`,
    slot: row.matched_plan_id || undefined,
    off: !row.matched_plan_id,
    match: !!row.matched,
    cat: row.category as RealEntry["cat"],
    sub: row.sub_category,
    title: row.description,
    desc: row.transcript || row.description,
    live: true,
  };
}
