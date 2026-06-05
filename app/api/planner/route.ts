import { NextResponse } from "next/server";
import { runPlannerAgent } from "@/lib/agents/planner-agent";

export async function POST(request: Request) {
  const body = await request.json();
  const output = await runPlannerAgent({
    userRequest: String(body.userRequest ?? ""),
    currentCalendar: Array.isArray(body.currentCalendar) ? body.currentCalendar : [],
    relevantPatterns: Array.isArray(body.relevantPatterns) ? body.relevantPatterns : []
  });
  return NextResponse.json(output);
}
