import { NextResponse } from "next/server";
import { getStoredSummary, upsertStoredSummary, type SummaryScope } from "@/lib/db/bogi-store";
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

export async function POST(request: Request) {
  const body = await request.json();
  const userId = String(body.userId ?? "");
  if (!userId) return NextResponse.json({ error: "userId required" }, { status: 400 });

  const scopeParam = String(body.scope ?? "day");
  const scope: SummaryScope = scopeParam === "week" || scopeParam === "month" ? scopeParam : "day";
  const date = String(body.date ?? new Date().toISOString().slice(0, 10));
  const summary = String(body.summary ?? "");
  const stats = typeof body.stats === "object" && body.stats !== null ? body.stats : {};
  const client = await createServerSupabaseClient();
  return NextResponse.json({
    summary: await upsertStoredSummary(client, { userId, scope, date, summary, stats })
  });
}
