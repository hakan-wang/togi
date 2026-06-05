import { NextResponse } from "next/server";
import { endScreenSession, startScreenSession } from "@/lib/db/bogi-store";
import { createServerSupabaseClient } from "@/lib/db/server";

export async function POST(request: Request) {
  const body = await request.json();
  const userId = String(body.userId ?? "");
  const plannedBlockId = String(body.plannedBlockId ?? "");
  if (!userId) return NextResponse.json({ error: "userId required" }, { status: 400 });
  if (!plannedBlockId) return NextResponse.json({ error: "plannedBlockId required" }, { status: 400 });

  const client = await createServerSupabaseClient();
  const screenSession = await startScreenSession(client, {
    userId,
    plannedBlockId,
    captureSurface: String(body.captureSurface ?? "browser"),
    rawFramesEnabled: Boolean(body.rawFramesEnabled ?? false)
  });
  return NextResponse.json({ screenSession });
}

export async function PATCH(request: Request) {
  const body = await request.json();
  const screenSessionId = String(body.screenSessionId ?? "");
  if (!screenSessionId) return NextResponse.json({ error: "screenSessionId required" }, { status: 400 });

  const endedAt = String(body.endedAt ?? new Date().toISOString());
  const client = await createServerSupabaseClient();
  const screenSession = await endScreenSession(client, screenSessionId, endedAt);
  return NextResponse.json({ screenSession });
}
