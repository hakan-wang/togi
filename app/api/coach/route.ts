import { NextResponse } from "next/server";
import { runCoachAgent } from "@/lib/agents/coach-agent";

export async function POST(request: Request) {
  const body = await request.json();
  const output = await runCoachAgent({
    message: String(body.message ?? ""),
    patterns: Array.isArray(body.patterns) ? body.patterns : [],
    logs: Array.isArray(body.logs) ? body.logs : []
  });
  return NextResponse.json(output);
}
