import { NextResponse } from "next/server";
import { exportUserData } from "@/lib/db/bogi-store";
import { createServerSupabaseClient } from "@/lib/db/server";

export async function GET(request: Request) {
  const userId = new URL(request.url).searchParams.get("userId");
  if (!userId) return NextResponse.json({ error: "userId required" }, { status: 400 });

  const client = await createServerSupabaseClient();
  return NextResponse.json(await exportUserData(client, userId));
}
