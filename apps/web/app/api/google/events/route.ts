/* /api/google/events
   GET    ?timeMin=ISO&timeMax=ISO   → list timed events in that window (defaults to today)
   POST   { title, startISO, endISO, note? }            → create
   PATCH  { id, title?, startISO?, endISO?, note? }      → update
   DELETE { id }                                         → delete

   Every handler resolves a valid access token (refreshing transparently). If the
   user isn't connected (or the refresh token died), returns 409 so the client can
   flip the UI back to "Connect".
   Note: event start/end MINUTES are computed client-side from the returned ISO
   strings, so they reflect the user's local timezone, not the server's. */
import { NextRequest, NextResponse } from "next/server";
import { getValidAccessToken, userIdFromRequest } from "../../../../lib/google-server";
import { createEvent, deleteEvent, listDayEvents, updateEvent } from "../../../../lib/google-calendar-api";

export const runtime = "nodejs";

async function tokenFor(req: NextRequest): Promise<{ userId: string; token: string } | NextResponse> {
  const userId = await userIdFromRequest(req);
  if (!userId) return NextResponse.json({ error: "Not signed in." }, { status: 401 });
  const token = await getValidAccessToken(userId);
  if (!token) return NextResponse.json({ error: "Calendar not connected.", code: "disconnected" }, { status: 409 });
  return { userId, token };
}

function handleApiError(e: any) {
  // a 401 from Google here means the token went bad mid-flight → treat as disconnected
  if (e?.status === 401) return NextResponse.json({ error: "Calendar disconnected.", code: "disconnected" }, { status: 409 });
  console.error("google events error:", e);
  return NextResponse.json({ error: e?.message || "Calendar request failed." }, { status: 502 });
}

export async function GET(req: NextRequest) {
  const auth = await tokenFor(req);
  if (auth instanceof NextResponse) return auth;
  const now = new Date();
  const startDefault = new Date(now); startDefault.setHours(0, 0, 0, 0);
  const endDefault = new Date(now); endDefault.setHours(23, 59, 59, 999);
  const timeMin = req.nextUrl.searchParams.get("timeMin") || startDefault.toISOString();
  const timeMax = req.nextUrl.searchParams.get("timeMax") || endDefault.toISOString();
  try {
    return NextResponse.json({ events: await listDayEvents(auth.token, timeMin, timeMax) });
  } catch (e) { return handleApiError(e); }
}

export async function POST(req: NextRequest) {
  const auth = await tokenFor(req);
  if (auth instanceof NextResponse) return auth;
  const b = await req.json().catch(() => ({}));
  if (!b.title || !b.startISO || !b.endISO) return NextResponse.json({ error: "title, startISO, endISO required." }, { status: 400 });
  try {
    return NextResponse.json({ event: await createEvent(auth.token, b) });
  } catch (e) { return handleApiError(e); }
}

export async function PATCH(req: NextRequest) {
  const auth = await tokenFor(req);
  if (auth instanceof NextResponse) return auth;
  const b = await req.json().catch(() => ({}));
  if (!b.id) return NextResponse.json({ error: "id required." }, { status: 400 });
  try {
    return NextResponse.json({ event: await updateEvent(auth.token, b.id, b) });
  } catch (e) { return handleApiError(e); }
}

export async function DELETE(req: NextRequest) {
  const auth = await tokenFor(req);
  if (auth instanceof NextResponse) return auth;
  const b = await req.json().catch(() => ({}));
  if (!b.id) return NextResponse.json({ error: "id required." }, { status: 400 });
  try {
    await deleteEvent(auth.token, b.id);
    return NextResponse.json({ ok: true });
  } catch (e) { return handleApiError(e); }
}
