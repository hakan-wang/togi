/* GET /api/google/connect
   Verifies the Supabase user (Bearer token) and returns the Google consent URL.
   The browser then navigates to that URL. We don't redirect here because a top-level
   navigation wouldn't carry the Supabase Authorization header. */
import { NextRequest, NextResponse } from "next/server";
import { buildConsentUrl, googleConfigured, userIdFromRequest } from "../../../../lib/google-server";

export const runtime = "nodejs";

export async function GET(req: NextRequest) {
  if (!googleConfigured()) {
    return NextResponse.json({ error: "Google Calendar isn’t configured on the server yet." }, { status: 503 });
  }
  const userId = await userIdFromRequest(req);
  if (!userId) return NextResponse.json({ error: "Not signed in." }, { status: 401 });

  const origin = req.nextUrl.origin;
  return NextResponse.json({ url: buildConsentUrl(userId, origin) });
}
