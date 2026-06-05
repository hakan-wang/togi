import { NextResponse } from "next/server";

const receivedFrameHashes = new Set<string>();

export async function POST(request: Request) {
  const form = await request.formData();
  const plannedBlockId = String(form.get("plannedBlockId") ?? "");
  const hash = String(form.get("hash") ?? "");
  const capturedAt = String(form.get("capturedAt") ?? "");

  if (!plannedBlockId || !hash || !capturedAt) {
    return NextResponse.json({ error: "missing required frame metadata" }, { status: 400 });
  }

  if (receivedFrameHashes.has(hash)) {
    return NextResponse.json({ accepted: false, reason: "duplicate" });
  }

  receivedFrameHashes.add(hash);
  return NextResponse.json({ accepted: true, plannedBlockId, capturedAt });
}
