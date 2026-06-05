import OpenAI from "openai";
import { NextResponse } from "next/server";

export async function POST(request: Request) {
  const form = await request.formData();
  const audio = form.get("audio");
  if (!(audio instanceof File)) {
    return NextResponse.json({ error: "audio file required" }, { status: 400 });
  }

  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const transcription = await client.audio.transcriptions.create({
    model: "gpt-4o-transcribe",
    file: audio
  });

  return NextResponse.json({ text: transcription.text });
}
