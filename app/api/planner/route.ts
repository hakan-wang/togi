import { NextResponse } from "next/server";
import { runPlannerAgent } from "@/lib/agents/planner-agent";
import { savePlannedBlocks } from "@/lib/db/bogi-store";
import { createServerSupabaseClient } from "@/lib/db/server";

export async function POST(request: Request) {
  const body = await request.json();
  const userId = String(body.userId ?? "");
  const output = await runPlannerAgent({
    userRequest: String(body.userRequest ?? ""),
    currentCalendar: Array.isArray(body.currentCalendar) ? body.currentCalendar : [],
    relevantPatterns: Array.isArray(body.relevantPatterns) ? body.relevantPatterns : []
  });
  const savedBlocks = userId
    ? await savePlannedBlocks(await createServerSupabaseClient(), userId, output.blocks)
    : [];
  return NextResponse.json({ ...output, savedBlocks });
}
