import { NextResponse } from "next/server";

export async function GET() {
  return NextResponse.json({
    plannedBlocks: [],
    realityLogs: [],
    screenObservationSummaries: [],
    dailySummaries: [],
    weeklySummaries: [],
    monthlySummaries: [],
    userPatterns: []
  });
}
