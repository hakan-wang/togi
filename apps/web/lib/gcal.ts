/* ============================================================
   Togi — Google Calendar client helpers (browser).
   The browser never talks to Google directly anymore. It calls Togi's own API
   routes (/api/google/*), which hold the OAuth tokens server-side and refresh them.
   This is the multi-user, persistent, read+write path:
     • startConnect()  → server-side OAuth consent (any user, their own calendar)
     • getStatus()     → is it configured / connected, and for which Google account
     • fetchTodayEvents / createEvent / updateEvent / deleteEvent  → read & edit
   ============================================================ */
import { Domain, PlanBlock } from "./data";
import { getSupabase } from "./supabase";

/** Supabase access token → Authorization header the API routes verify. */
async function authHeaders(): Promise<Record<string, string>> {
  const sb = getSupabase();
  if (!sb) return {};
  try {
    const { data } = await sb.auth.getSession();
    const t = data.session?.access_token;
    return t ? { Authorization: `Bearer ${t}` } : {};
  } catch { return {}; }
}

export interface GcalStatus { configured: boolean; connected: boolean; email: string | null; }

export async function getStatus(): Promise<GcalStatus> {
  try {
    const res = await fetch("/api/google/status", { headers: await authHeaders() });
    if (!res.ok && res.status !== 401) return { configured: false, connected: false, email: null };
    return await res.json();
  } catch { return { configured: false, connected: false, email: null }; }
}

/** Kick off the server-side OAuth flow: get the consent URL, then navigate to it. */
export async function startConnect(): Promise<void> {
  const res = await fetch("/api/google/connect", { headers: await authHeaders() });
  if (!res.ok) {
    const { error } = await res.json().catch(() => ({ error: "" }));
    throw new Error(error || "Couldn’t start Google sign-in.");
  }
  const { url } = await res.json();
  window.location.assign(url);
}

export async function disconnect(): Promise<void> {
  await fetch("/api/google/disconnect", { method: "POST", headers: await authHeaders() });
}

/* ---------- domain heuristic (same spirit as before) ---------- */
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

// minutes from local midnight — computed in the BROWSER so it's the user's timezone
const minsOf = (iso: string) => { const d = new Date(iso); return d.getHours() * 60 + d.getMinutes(); };

interface ApiEvent { id: string; title: string; note?: string; startISO: string; endISO: string; }

function toBlock(e: ApiEvent): PlanBlock {
  return {
    id: `gcal-${e.id}`, source: "gcal", gcalId: e.id,
    domain: guessDomain(e.title), project: null, activity: "Scheduled",
    title: e.title, note: e.note || undefined,
    start: minsOf(e.startISO), end: minsOf(e.endISO),
    startISO: e.startISO, endISO: e.endISO,
  };
}

/** Custom error so the UI can flip back to "Connect" when the server says 409. */
export class CalendarDisconnected extends Error { constructor() { super("Calendar disconnected"); } }

async function call(path: string, init?: RequestInit) {
  const res = await fetch(path, { ...init, headers: { ...(init?.headers || {}), ...(await authHeaders()) } });
  if (res.status === 409) throw new CalendarDisconnected();
  if (!res.ok) {
    const { error } = await res.json().catch(() => ({ error: "" }));
    throw new Error(error || `Calendar request failed (${res.status}).`);
  }
  return res.json();
}

/** Today's timed primary-calendar events, as plan blocks. */
export async function fetchTodayEvents(): Promise<PlanBlock[]> {
  const start = new Date(); start.setHours(0, 0, 0, 0);
  const end = new Date(); end.setHours(23, 59, 59, 999);
  const q = new URLSearchParams({ timeMin: start.toISOString(), timeMax: end.toISOString() });
  const { events } = await call(`/api/google/events?${q.toString()}`);
  return (events as ApiEvent[]).map(toBlock);
}

export async function createEvent(ev: { title: string; startISO: string; endISO: string; note?: string }): Promise<PlanBlock> {
  const { event } = await call(`/api/google/events`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(ev) });
  return toBlock(event);
}

export async function updateEvent(id: string, patch: { title?: string; startISO?: string; endISO?: string; note?: string }): Promise<PlanBlock> {
  const { event } = await call(`/api/google/events`, { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id, ...patch }) });
  return toBlock(event);
}

export async function deleteEvent(id: string): Promise<void> {
  await call(`/api/google/events`, { method: "DELETE", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id }) });
}
