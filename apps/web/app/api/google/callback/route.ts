/* GET /api/google/callback?code=...&state=...
   Google redirects here after consent. We verify the signed state (→ user id),
   exchange the code for tokens, store them, then bounce back to the app. */
import { NextRequest, NextResponse } from "next/server";
import { exchangeCodeAndStore, verifyState } from "../../../../lib/google-server";

export const runtime = "nodejs";

function back(origin: string, status: string) {
  return NextResponse.redirect(`${origin}/?gcal=${status}`);
}

export async function GET(req: NextRequest) {
  const origin = req.nextUrl.origin;
  const code = req.nextUrl.searchParams.get("code");
  const state = req.nextUrl.searchParams.get("state");
  const error = req.nextUrl.searchParams.get("error");

  if (error) return back(origin, "denied");
  if (!code || !state) return back(origin, "error");

  const userId = verifyState(state);
  if (!userId) return back(origin, "error");

  try {
    await exchangeCodeAndStore(code, userId, origin);
    return back(origin, "connected");
  } catch (e) {
    console.error("google callback failed:", e);
    return back(origin, "error");
  }
}
