import { NextResponse } from "next/server";
import { runCoachAgent } from "@/lib/agents/coach-agent";
import { saveAgentRun } from "@/lib/db/bogi-store";
import { createServerSupabaseClient } from "@/lib/db/server";

export async function POST(request: Request) {
  const body = await request.json();
  const userId = String(body.userId ?? "");
  const input = {
    message: String(body.message ?? ""),
    patterns: Array.isArray(body.patterns) ? body.patterns : [],
    logs: Array.isArray(body.logs) ? body.logs : []
  };
  const output = await runCoachAgent(input);
  const agentRun = userId
    ? await saveAgentRun(await createServerSupabaseClient(), {
      userId,
      agentName: "coach_agent",
      input,
      output,
      status: "succeeded"
    })
    : null;
  return NextResponse.json({ ...output, agentRun });
}
