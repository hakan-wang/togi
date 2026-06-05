import { NextResponse } from "next/server";
import { runScreenObserverAgent } from "@/lib/agents/screen-observer-agent";
import { saveAgentRun, saveScreenFrameBatch, saveScreenObservationSummary } from "@/lib/db/bogi-store";
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
  const batchReady = String(form.get("batchReady") ?? "") === "true";
  const timeWindowStart = String(form.get("timeWindowStart") ?? capturedAt);
  const timeWindowEnd = String(form.get("timeWindowEnd") ?? capturedAt);

  if (!plannedBlockId || !hash || !capturedAt) {
    return NextResponse.json({ error: "missing required frame metadata" }, { status: 400 });
  }

  if (receivedFrameHashes.has(hash)) {
    return NextResponse.json({ accepted: false, reason: "duplicate" });
  }

  receivedFrameHashes.add(hash);
  const client = userId ? await createServerSupabaseClient() : null;
  if (client) {
    await saveScreenFrameBatch(client, {
      userId,
      plannedBlockId,
      screenSessionId: screenSessionId || null,
      hash,
      capturedAt
    });
  }

  let observationSummary = null;
  let savedObservationSummary = null;
  let agentRun = null;
  if (batchReady && screenSessionId) {
    const framesJson = String(form.get("framesJson") ?? "[]");
    const frames = JSON.parse(framesJson) as Array<{ capturedAt: string; imageBase64: string }>;
    const observerInput = { blockId: plannedBlockId, frames };
    observationSummary = await runScreenObserverAgent(observerInput);
    if (client) {
      savedObservationSummary = await saveScreenObservationSummary(client, {
        plannedBlockId,
        screenSessionId,
        timeWindowStart,
        timeWindowEnd,
        observation: observationSummary
      });
      agentRun = await saveAgentRun(client, {
        userId,
        agentName: "screen_observer_agent",
        input: observerInput,
        output: observationSummary,
        status: "succeeded"
      });
    }
  }

  return NextResponse.json({
    accepted: true,
    plannedBlockId,
    capturedAt,
    workflowEvent: frameBatchReadyEvent,
    observationSummary,
    savedObservationSummary,
    agentRun
  });
}
