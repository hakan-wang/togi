import { NextResponse } from "next/server";
import { deleteUserData } from "@/lib/db/bogi-store";
import { createServerSupabaseClient } from "@/lib/db/server";

export async function POST(request: Request) {
  const body = await request.json();
  const userId = String(body.userId ?? "");
  if (!userId) return NextResponse.json({ error: "userId required" }, { status: 400 });

  const client = await createServerSupabaseClient();
  await deleteUserData(client, userId);
  return NextResponse.json({ deleted: true });
}
