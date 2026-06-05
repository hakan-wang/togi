import { NextResponse } from "next/server";
import { runRealityLogAgent } from "@/lib/agents/reality-log-agent";
import { saveAgentRun, saveRealityLog } from "@/lib/db/bogi-store";
import { createServerSupabaseClient } from "@/lib/db/server";

export async function POST(request: Request) {
  const body = await request.json();
  const userId = String(body.userId ?? "");
  const input = {
    plannedBlockId: String(body.plannedBlockId ?? ""),
    plannedTitle: String(body.plannedTitle ?? ""),
    observationSummary: String(body.observationSummary ?? ""),
    userCorrection: String(body.userCorrection ?? "")
  };
  const output = await runRealityLogAgent(input);
  const client = userId ? await createServerSupabaseClient() : null;
  const savedRealityLog = client ? await saveRealityLog(client, userId, output) : null;
  const agentRun = client
    ? await saveAgentRun(client, {
      userId,
      agentName: "reality_log_agent",
      input,
      output,
      status: "succeeded"
    })
    : null;
  return NextResponse.json({ ...output, savedRealityLog, agentRun });
}
