import { NextResponse } from "next/server";
import { runRealityLogAgent } from "@/lib/agents/reality-log-agent";

export async function POST(request: Request) {
  const body = await request.json();
  const output = await runRealityLogAgent({
    plannedBlockId: String(body.plannedBlockId ?? ""),
    plannedTitle: String(body.plannedTitle ?? ""),
    observationSummary: String(body.observationSummary ?? ""),
    userCorrection: String(body.userCorrection ?? "")
  });
  return NextResponse.json(output);
}
