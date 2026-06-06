/* ============================================================
   Togi — Supabase browser client (lazy, optional).
   Returns null if env vars aren't set yet, so the app still runs (with the
   local-storage fallback in store.ts) before credentials land.
   ============================================================ */
import { createClient, SupabaseClient } from "@supabase/supabase-js";

let _client: SupabaseClient | null | undefined;

export function getSupabase(): SupabaseClient | null {
  if (_client !== undefined) return _client;
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  _client = url && anon ? createClient(url, anon) : null;
  return _client;
}

export const supabaseConfigured = () =>
  !!(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);
