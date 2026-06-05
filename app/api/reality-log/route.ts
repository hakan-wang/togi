import { NextResponse } from "next/server";
import { runRealityLogAgent } from "@/lib/agents/reality-log-agent";
import { saveRealityLog } from "@/lib/db/bogi-store";
import { createServerSupabaseClient } from "@/lib/db/server";

export async function POST(request: Request) {
  const body = await request.json();
  const userId = String(body.userId ?? "");
  const output = await runRealityLogAgent({
    plannedBlockId: String(body.plannedBlockId ?? ""),
    plannedTitle: String(body.plannedTitle ?? ""),
    observationSummary: String(body.observationSummary ?? ""),
    userCorrection: String(body.userCorrection ?? "")
  });
  const savedRealityLog = userId
    ? await saveRealityLog(await createServerSupabaseClient(), userId, output)
    : null;
  return NextResponse.json({ ...output, savedRealityLog });
}
