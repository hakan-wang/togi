/* ============================================================
   Togi — thin Google Calendar API v3 wrapper (server-side).
   Given a valid access token, read/create/update/delete events on the user's
   primary calendar, and map Google events ↔ Togi plan blocks.
   (Primary calendar only for now; structured so multi-calendar can slot in later.)
   ============================================================ */
const BASE = "https://www.googleapis.com/calendar/v3";

export interface TogiEvent {
  id: string;            // raw Google event id
  title: string;
  note?: string;         // location/description
  start: number;         // minutes from midnight (local)
  end: number;           // minutes from midnight (local)
  startISO: string;
  endISO: string;
  htmlLink?: string;
}

function minsOf(iso: string): number {
  const d = new Date(iso);
  return d.getHours() * 60 + d.getMinutes();
}

async function gcal(token: string, path: string, init?: RequestInit) {
  const res = await fetch(`${BASE}${path}`, {
    ...init,
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", ...(init?.headers || {}) },
  });
  if (!res.ok) {
    const body = await res.text();
    const err: any = new Error(`Calendar API ${res.status}: ${body}`);
    err.status = res.status;
    throw err;
  }
  return res.status === 204 ? null : res.json();
}

/** List a single day's timed events (skips all-day) on the primary calendar. */
export async function listDayEvents(token: string, dayStartISO: string, dayEndISO: string): Promise<TogiEvent[]> {
  const q = new URLSearchParams({
    singleEvents: "true",
    orderBy: "startTime",
    timeMin: dayStartISO,
    timeMax: dayEndISO,
  });
  const data = await gcal(token, `/calendars/primary/events?${q.toString()}`);
  return (data.items || [])
    .filter((e: any) => e.start?.dateTime && e.end?.dateTime) // timed events only
    .map((e: any): TogiEvent => ({
      id: e.id,
      title: e.summary || "Busy",
      note: e.location || e.description || undefined,
      start: minsOf(e.start.dateTime),
      end: minsOf(e.end.dateTime),
      startISO: e.start.dateTime,
      endISO: e.end.dateTime,
      htmlLink: e.htmlLink,
    }));
}

export async function createEvent(token: string, ev: { title: string; startISO: string; endISO: string; note?: string }): Promise<TogiEvent> {
  const body = {
    summary: ev.title,
    description: ev.note || undefined,
    start: { dateTime: ev.startISO },
    end: { dateTime: ev.endISO },
  };
  const e = await gcal(token, `/calendars/primary/events`, { method: "POST", body: JSON.stringify(body) });
  return { id: e.id, title: e.summary || ev.title, note: e.description, start: minsOf(e.start.dateTime), end: minsOf(e.end.dateTime), startISO: e.start.dateTime, endISO: e.end.dateTime, htmlLink: e.htmlLink };
}

export async function updateEvent(token: string, id: string, patch: { title?: string; startISO?: string; endISO?: string; note?: string }): Promise<TogiEvent> {
  const body: Record<string, any> = {};
  if (patch.title !== undefined) body.summary = patch.title;
  if (patch.note !== undefined) body.description = patch.note;
  if (patch.startISO) body.start = { dateTime: patch.startISO };
  if (patch.endISO) body.end = { dateTime: patch.endISO };
  const e = await gcal(token, `/calendars/primary/events/${encodeURIComponent(id)}`, { method: "PATCH", body: JSON.stringify(body) });
  return { id: e.id, title: e.summary || "Busy", note: e.description, start: minsOf(e.start.dateTime), end: minsOf(e.end.dateTime), startISO: e.start.dateTime, endISO: e.end.dateTime, htmlLink: e.htmlLink };
}

export async function deleteEvent(token: string, id: string): Promise<void> {
  await gcal(token, `/calendars/primary/events/${encodeURIComponent(id)}`, { method: "DELETE" });
}
