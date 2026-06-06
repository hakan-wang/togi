/* ============================================================
   POST /api/transcribe  — audio (multipart "audio") → { text }
   Server-side speech-to-text, so the API key never reaches the browser.

   Provider: prefers Groq (free tier, fast Whisper) when GROQ_API_KEY is set,
   else falls back to OpenAI Whisper (OPENAI_API_KEY). Both speak the same
   OpenAI-style audio API, so it's one code path with different base URLs.
   Language is auto-detected (handles Swedish + English).
   ============================================================ */
import { NextRequest, NextResponse } from "next/server";
import OpenAI from "openai";

export const runtime = "nodejs";
export const maxDuration = 30;

function provider() {
  if (process.env.GROQ_API_KEY) {
    return { key: process.env.GROQ_API_KEY, baseURL: "https://api.groq.com/openai/v1", model: "whisper-large-v3-turbo" };
  }
  if (process.env.OPENAI_API_KEY) {
    return { key: process.env.OPENAI_API_KEY, baseURL: undefined, model: "whisper-1" };
  }
  return null;
}

export async function POST(req: NextRequest) {
  const p = provider();
  if (!p) {
    return NextResponse.json(
      { error: "no_stt_key", message: "Set GROQ_API_KEY (free) or OPENAI_API_KEY in apps/web/.env.local to enable voice. Use 'type instead' meanwhile." },
      { status: 503 },
    );
  }
  try {
    const form = await req.formData();
    const file = form.get("audio");
    if (!(file instanceof File)) return NextResponse.json({ error: "no_audio" }, { status: 400 });

    const client = new OpenAI({ apiKey: p.key, baseURL: p.baseURL });
    const result = await client.audio.transcriptions.create({ file, model: p.model });
    return NextResponse.json({ text: result.text || "" });
  } catch (e: any) {
    console.error("transcribe error", e);
    return NextResponse.json({ error: "transcribe_failed", message: String(e?.message || e) }, { status: 502 });
  }
}
