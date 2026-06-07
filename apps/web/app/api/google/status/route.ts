/* GET /api/google/status → { configured, connected, email } */
import { NextRequest, NextResponse } from "next/server";
import { getConnection, googleConfigured, userIdFromRequest } from "../../../../lib/google-server";

export const runtime = "nodejs";

export async function GET(req: NextRequest) {
  const configured = googleConfigured();
  if (!configured) return NextResponse.json({ configured: false, connected: false, email: null });

  const userId = await userIdFromRequest(req);
  if (!userId) return NextResponse.json({ configured, connected: false, email: null }, { status: 401 });

  const conn = await getConnection(userId);
  return NextResponse.json({ configured, connected: !!conn, email: conn?.google_email ?? null });
}
