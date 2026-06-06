/* ============================================================
   POST /api/transcribe  — audio (multipart "audio") → { text }
   Server-side OpenAI Whisper, so the API key never reaches the browser.
   ============================================================ */
import { NextRequest, NextResponse } from "next/server";
import OpenAI from "openai";

export const runtime = "nodejs";
export const maxDuration = 30;

export async function POST(req: NextRequest) {
  const key = process.env.OPENAI_API_KEY;
  if (!key) {
    return NextResponse.json(
      { error: "no_openai_key", message: "OPENAI_API_KEY is not set. Add it to apps/web/.env.local to enable voice. Use 'type instead' meanwhile." },
      { status: 503 },
    );
  }
  try {
    const form = await req.formData();
    const file = form.get("audio");
    if (!(file instanceof File)) {
      return NextResponse.json({ error: "no_audio" }, { status: 400 });
    }
    const openai = new OpenAI({ apiKey: key });
    const result = await openai.audio.transcriptions.create({
      file,
      model: "whisper-1",
      language: "en",
    });
    return NextResponse.json({ text: result.text || "" });
  } catch (e: any) {
    console.error("transcribe error", e);
    return NextResponse.json({ error: "transcribe_failed", message: String(e?.message || e) }, { status: 502 });
  }
}
