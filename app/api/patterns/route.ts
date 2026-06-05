import { NextResponse } from "next/server";
import { getRelevantPatterns, upsertUserPattern } from "@/lib/db/bogi-store";
import { createServerSupabaseClient } from "@/lib/db/server";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const userId = url.searchParams.get("userId");
  const category = url.searchParams.get("category") ?? "";
  if (!userId) return NextResponse.json({ error: "userId required" }, { status: 400 });
  if (!category) return NextResponse.json({ error: "category required" }, { status: 400 });

  const client = await createServerSupabaseClient();
  return NextResponse.json({ patterns: await getRelevantPatterns(client, userId, category) });
}

export async function POST(request: Request) {
  const body = await request.json();
  const userId = String(body.userId ?? "");
  if (!userId) return NextResponse.json({ error: "userId required" }, { status: 400 });

  const pattern = {
    patternKey: String(body.patternKey ?? ""),
    evidence: typeof body.evidence === "object" && body.evidence !== null ? body.evidence : {},
    recommendation: String(body.recommendation ?? "")
  };
  const client = await createServerSupabaseClient();
  return NextResponse.json({ pattern: await upsertUserPattern(client, userId, pattern) });
}
