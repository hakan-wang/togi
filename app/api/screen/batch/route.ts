import { NextResponse } from "next/server";
import { saveScreenFrameBatch } from "@/lib/db/bogi-store";
import { createServerSupabaseClient } from "@/lib/db/server";
import { frameBatchReadyEvent } from "@/lib/workflows/frame-batch-ready";

const receivedFrameHashes = new Set<string>();

export async function POST(request: Request) {
  const form = await request.formData();
  const plannedBlockId = String(form.get("plannedBlockId") ?? "");
  const userId = String(form.get("userId") ?? "");
  const screenSessionId = String(form.get("screenSessionId") ?? "");
  const hash = String(form.get("hash") ?? "");
  const capturedAt = String(form.get("capturedAt") ?? "");

  if (!plannedBlockId || !hash || !capturedAt) {
    return NextResponse.json({ error: "missing required frame metadata" }, { status: 400 });
  }

  if (receivedFrameHashes.has(hash)) {
    return NextResponse.json({ accepted: false, reason: "duplicate" });
  }

  receivedFrameHashes.add(hash);
  if (userId) {
    const client = await createServerSupabaseClient();
    await saveScreenFrameBatch(client, {
      userId,
      plannedBlockId,
      screenSessionId: screenSessionId || null,
      hash,
      capturedAt
    });
  }

  return NextResponse.json({
    accepted: true,
    plannedBlockId,
    capturedAt,
    workflowEvent: frameBatchReadyEvent
  });
}
