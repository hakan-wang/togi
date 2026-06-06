/* ============================================================
   Togi — Google Calendar (read-only) via Google Identity Services (GIS).
   Lightest setup: just a public Web OAuth Client ID (no secret). The GIS token
   client returns a short-lived access token for the Calendar API, used client-side.
   Set NEXT_PUBLIC_GOOGLE_CLIENT_ID in .env.local.
   ============================================================ */
import { Domain, PlanBlock } from "./data";

declare global { interface Window { google?: any; } }

const SCOPE = "https://www.googleapis.com/auth/calendar.events.readonly";

export function calendarConfigured(): boolean {
  return !!process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID;
}

/** Pop the Google consent/token flow and resolve a Calendar access token. */
export function getCalendarToken(): Promise<string> {
  return new Promise((resolve, reject) => {
    const cid = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID;
    if (!cid) return reject(new Error("Google Client ID isn’t set yet (NEXT_PUBLIC_GOOGLE_CLIENT_ID)."));
    const oauth = typeof window !== "undefined" && window.google?.accounts?.oauth2;
    if (!oauth) return reject(new Error("Google sign-in didn’t load — refresh and try again."));
    try {
      const client = oauth.initTokenClient({
        client_id: cid,
        scope: SCOPE,
        callback: (resp: any) => (resp?.error ? reject(new Error(resp.error)) : resolve(resp.access_token)),
      });
      client.requestAccessToken({ prompt: "" });
    } catch (e: any) { reject(e); }
  });
}

const DOMAIN_HINTS: Array<[RegExp, Domain]> = [
  [/gym|run|workout|yoga|doctor|dentist|training/i, "Health"],
  [/lunch|dinner|coffee|party|birthday|family|friend|date/i, "Social"],
  [/class|lecture|seminar|study|exam|course/i, "Study"],
  [/shop|errand|pickup|drop|commute|travel|flight|appointment/i, "Errands & life admin"],
  [/movie|game|hobby|read/i, "Leisure"],
];
function guessDomain(title: string): Domain {
  for (const [re, d] of DOMAIN_HINTS) if (re.test(title)) return d;
  return "Work";
}

/** Fetch today's primary-calendar events and map them to plan blocks. */
export async function fetchTodayEvents(token: string): Promise<PlanBlock[]> {
  const start = new Date(); start.setHours(0, 0, 0, 0);
  const end = new Date(); end.setHours(23, 59, 59, 999);
  const url = `https://www.googleapis.com/calendar/v3/calendars/primary/events?singleEvents=true&orderBy=startTime&timeMin=${start.toISOString()}&timeMax=${end.toISOString()}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!res.ok) throw new Error(`Calendar API error (${res.status})`);
  const data = await res.json();
  const mins = (iso: string) => { const d = new Date(iso); return d.getHours() * 60 + d.getMinutes(); };
  return (data.items || [])
    .filter((e: any) => e.start?.dateTime && e.end?.dateTime) // skip all-day events
    .map((e: any, i: number): PlanBlock => {
      const title = e.summary || "Busy";
      return { id: `gcal-${e.id || i}`, domain: guessDomain(title), project: null, activity: "Scheduled", title, note: e.location || undefined, start: mins(e.start.dateTime), end: mins(e.end.dateTime) };
    });
}
