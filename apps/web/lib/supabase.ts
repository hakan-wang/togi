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

/**
 * Ensure there's a session so Supabase RLS works and the backend gets an auth token —
 * with no login screen. Uses anonymous sign-in (enable "Anonymous sign-ins" in
 * Supabase → Authentication → Providers). Safe no-op when Supabase isn't configured.
 */
let _signingIn: Promise<void> | null = null;
export async function ensureSession(): Promise<SupabaseClient | null> {
  const sb = getSupabase();
  if (!sb) return null;
  try {
    const { data } = await sb.auth.getSession();
    if (!data.session) {
      if (!_signingIn) _signingIn = sb.auth.signInAnonymously().then(() => undefined).catch(() => undefined);
      await _signingIn;
    }
  } catch { /* offline / anon disabled → caller falls back to localStorage */ }
  return sb;
}
