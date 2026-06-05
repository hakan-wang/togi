import { NextResponse } from "next/server";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const scope = url.searchParams.get("scope") ?? "day";
  return NextResponse.json({
    scope,
    summary: "Planned work, confirmed reality, and gaps will appear here.",
    stats: {
      plannedMinutes: 360,
      confirmedRealityMinutes: 282,
      gapMinutes: 78
    }
  });
}
