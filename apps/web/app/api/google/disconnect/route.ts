/* POST /api/google/disconnect → revoke at Google + delete the stored connection. */
import { NextRequest, NextResponse } from "next/server";
import { disconnect, userIdFromRequest } from "../../../../lib/google-server";

export const runtime = "nodejs";

export async function POST(req: NextRequest) {
  const userId = await userIdFromRequest(req);
  if (!userId) return NextResponse.json({ error: "Not signed in." }, { status: 401 });
  await disconnect(userId);
  return NextResponse.json({ ok: true });
}
