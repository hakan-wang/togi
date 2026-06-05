import { NextResponse } from "next/server";
import { runPlannerAgent } from "@/lib/agents/planner-agent";
import { saveAgentRun, savePlannedBlocks } from "@/lib/db/bogi-store";
import { createServerSupabaseClient } from "@/lib/db/server";

export async function POST(request: Request) {
  const body = await request.json();
  const userId = String(body.userId ?? "");
  const input = {
    userRequest: String(body.userRequest ?? ""),
    currentCalendar: Array.isArray(body.currentCalendar) ? body.currentCalendar : [],
    relevantPatterns: Array.isArray(body.relevantPatterns) ? body.relevantPatterns : []
  };
  const output = await runPlannerAgent(input);
  const client = userId ? await createServerSupabaseClient() : null;
  const savedBlocks = client ? await savePlannedBlocks(client, userId, output.blocks) : [];
  const agentRun = client
    ? await saveAgentRun(client, {
      userId,
      agentName: "planner_agent",
      input,
      output,
      status: "succeeded"
    })
    : null;
  return NextResponse.json({ ...output, savedBlocks, agentRun });
}
