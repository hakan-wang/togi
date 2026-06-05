import { NextResponse } from "next/server";
import { getStoredSummary, type SummaryScope } from "@/lib/db/bogi-store";
import { createServerSupabaseClient } from "@/lib/db/server";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const userId = url.searchParams.get("userId");
  if (!userId) return NextResponse.json({ error: "userId required" }, { status: 400 });

  const scopeParam = url.searchParams.get("scope") ?? "day";
  const scope: SummaryScope = scopeParam === "week" || scopeParam === "month" ? scopeParam : "day";
  const date = url.searchParams.get("date") ?? new Date().toISOString().slice(0, 10);
  const client = await createServerSupabaseClient();
  return NextResponse.json(await getStoredSummary(client, { userId, scope, date }));
}
