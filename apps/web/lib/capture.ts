/* ============================================================
   Togi — client-side capture pipeline helpers.
   transcribeAudio() → POST /api/transcribe (OpenAI Whisper, server-side)
   categorizeText()  → POST /api/categorize (existing backend /v1/infer, server-side)
   Both go through Next.js API routes so keys/tokens never touch the browser.
   ============================================================ */
import { CategoryKey } from "./data";
import { getSupabase } from "./supabase";

export interface CategorizeResult {
  category: CategoryKey;
  subCategory: string;
  description: string;
  durationMin: number | null;
  matchedPlanId: string | null;
  matched: boolean;
}

export interface CheckinContext {
  block?: string;      // the block that just ended, e.g. "Formula v3 doc"
  planId?: string;     // its plan id, for matching
  window?: string;     // e.g. "11:15–12:00"
  kind?: string;       // checkin | self | ask | plan
}

export async function transcribeAudio(blob: Blob): Promise<string> {
  const fd = new FormData();
  fd.append("audio", blob, "checkin.webm");
  const res = await fetch("/api/transcribe", { method: "POST", body: fd });
  if (!res.ok) throw new Error(`transcribe failed (${res.status})`);
  const json = await res.json();
  return (json.text || "").trim();
}

export async function categorizeText(text: string, ctx: CheckinContext = {}): Promise<CategorizeResult> {
  // Pass the Supabase access token (if signed in) so the backend authorizes the Claude call.
  let token: string | undefined;
  try {
    const sb = getSupabase();
    if (sb) token = (await sb.auth.getSession()).data.session?.access_token;
  } catch { /* ignore */ }

  const res = await fetch("/api/categorize", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text, context: ctx, token }),
  });
  if (!res.ok) throw new Error(`categorize failed (${res.status})`);
  return (await res.json()) as CategorizeResult;
}
