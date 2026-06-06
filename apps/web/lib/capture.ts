/* ============================================================
   Togi — client-side capture pipeline helpers.
   transcribeAudio() → POST /api/transcribe (Groq/OpenAI Whisper)
   categorizeText()  → POST /api/categorize (categorizer per spec), passing the
   user's existing projects + activities so the LLM reuses labels.
   ============================================================ */
import { Domain } from "./data";
import { Vocabulary } from "./store";

export interface CategorizeResult {
  title: string;
  domain: Domain;
  project: string | null;
  activity: string;
  note: string | null;
  confidence: number;
  clarify_question: string | null;
  matched: boolean;
  durationMin: number | null;
  via?: string;
}

export interface CheckinContext {
  block?: string;
  planId?: string;
  window?: string;
  kind?: string;
}

export async function transcribeAudio(blob: Blob): Promise<string> {
  const fd = new FormData();
  fd.append("audio", blob, "checkin.webm");
  const res = await fetch("/api/transcribe", { method: "POST", body: fd });
  if (!res.ok) throw new Error(`transcribe failed (${res.status})`);
  const json = await res.json();
  return (json.text || "").trim();
}

export async function categorizeText(text: string, ctx: CheckinContext, vocab: Vocabulary): Promise<CategorizeResult> {
  const res = await fetch("/api/categorize", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text, context: ctx, projects: vocab.projects, activities: vocab.activities }),
  });
  if (!res.ok) throw new Error(`categorize failed (${res.status})`);
  return (await res.json()) as CategorizeResult;
}
