import { NextResponse } from "next/server";
import { createGoogleOAuthClient, exchangeGoogleOAuthCode } from "@/lib/calendar/google-calendar";
import { saveCalendarConnection } from "@/lib/db/bogi-store";
import { createServerSupabaseClient } from "@/lib/db/server";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const userId = url.searchParams.get("state");
  if (!code) return NextResponse.json({ error: "code required" }, { status: 400 });
  if (!userId) return NextResponse.json({ error: "state user id required" }, { status: 400 });

  const tokens = await exchangeGoogleOAuthCode(createGoogleOAuthClient(), code);
  const client = await createServerSupabaseClient();
  await saveCalendarConnection(client, userId, tokens);
  return NextResponse.redirect(new URL("/settings?calendar=connected", url.origin));
}
