/* ============================================================
   Togi — demo day data + the categorization model (per togi_categorization_spec.md).
   Four independent fields per entry: domain (fixed 7) · project · activity · note.
   Times are minutes from midnight.

   The "Formula v3 doc" real block is intentionally omitted from the seed — it's the
   block the live vertical-slice check-in fills.
   ============================================================ */

export const hm = (h: number, m = 0) => h * 60 + m;
export function fmt(min: number) {
  const h = Math.floor(min / 60), m = min % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

/* ---------- The 7 fixed domains (the only top-level bucket; drives color) ---------- */
export type Domain =
  | "Work" | "Study" | "Health" | "Social" | "Errands & life admin" | "Leisure" | "Distraction";

export const DOMAINS: Record<Domain, { label: string; color: string; tint: string }> = {
  "Work": { label: "Work", color: "var(--cat-deepwork)", tint: "var(--cat-deepwork-t)" },
  "Study": { label: "Study", color: "var(--cat-creative)", tint: "var(--cat-creative-t)" },
  "Health": { label: "Health", color: "var(--cat-health)", tint: "var(--cat-health-t)" },
  "Social": { label: "Social", color: "var(--cat-social)", tint: "var(--cat-social-t)" },
  "Errands & life admin": { label: "Errands & life admin", color: "var(--cat-errands)", tint: "var(--cat-errands-t)" },
  "Leisure": { label: "Leisure", color: "var(--cat-leisure)", tint: "var(--cat-leisure-t)" },
  "Distraction": { label: "Distraction", color: "var(--cat-scroll)", tint: "var(--cat-scroll-t)" },
};
export const DOMAIN_KEYS = Object.keys(DOMAINS) as Domain[];
/** Short label for chips/legends (the long one is unwieldy). */
export const domainShort = (d: Domain) => (d === "Errands & life admin" ? "Errands" : d);

/* ---------- Starter activity vocabulary (seeded per user; grows over time) ---------- */
export const STARTER_ACTIVITIES = [
  "Editing", "Filming", "Writing", "Email", "Meeting", "Planning", "Deep work", "Admin",
  "Studying", "Reading", "Gym", "Walk", "Cooking", "Eating", "Commuting", "Errands",
  "Cleaning", "Hanging out", "Call", "Gaming", "Watching", "Scrolling", "Resting",
];

/* ---------- Legacy 9-category palette — used ONLY by the scripted session overlay and
   the mock Insights data-bank chart. The live app uses DOMAINS. ---------- */
export const CATEGORIES: Record<string, { key: string; label: string; color: string; tint: string }> = {
  deepwork: { key: "deepwork", label: "Deep work", color: "var(--cat-deepwork)", tint: "var(--cat-deepwork-t)" },
  creative: { key: "creative", label: "Creative", color: "var(--cat-creative)", tint: "var(--cat-creative-t)" },
  admin: { key: "admin", label: "Admin & email", color: "var(--cat-admin)", tint: "var(--cat-admin-t)" },
  health: { key: "health", label: "Health", color: "var(--cat-health)", tint: "var(--cat-health-t)" },
  social: { key: "social", label: "Friends", color: "var(--cat-social)", tint: "var(--cat-social-t)" },
  errands: { key: "errands", label: "Errands", color: "var(--cat-errands)", tint: "var(--cat-errands-t)" },
  leisure: { key: "leisure", label: "Leisure", color: "var(--cat-leisure)", tint: "var(--cat-leisure-t)" },
  scroll: { key: "scroll", label: "Scrolling", color: "var(--cat-scroll)", tint: "var(--cat-scroll-t)" },
  personal: { key: "personal", label: "Personal", color: "var(--cat-personal)", tint: "var(--cat-personal-t)" },
};

export interface PlanBlock {
  id: string; domain: Domain; project?: string | null; activity: string; title: string; note?: string; start: number; end: number;
  // Set when the block originates from Google Calendar (enables write-back editing).
  source?: "gcal"; gcalId?: string; startISO?: string; endISO?: string;
}

export const PLAN: PlanBlock[] = [
  { id: "p1", domain: "Health", project: null, activity: "Gym", title: "Strength session", note: "Push day", start: hm(7, 30), end: hm(8, 15) },
  { id: "p2", domain: "Work", project: "Litro", activity: "Editing", title: "Edit launch vlog", note: "Cut the Litro launch video", start: hm(8, 30), end: hm(10, 30) },
  { id: "p3", domain: "Work", project: "Litro", activity: "Email", title: "Email co-manufacturers", note: "Chase the sample timeline", start: hm(10, 30), end: hm(11, 15) },
  { id: "p4", domain: "Work", project: "Litro", activity: "Writing", title: "Formula v3 doc", note: "Finish the write-up", start: hm(11, 15), end: hm(12, 0) },
  /* 12:00–14:00 : intentionally empty — tap to self check-in */
  { id: "p5", domain: "Errands & life admin", project: null, activity: "Errands", title: "Post office + shop", note: "Drop the returns", start: hm(14, 0), end: hm(15, 0) },
  { id: "p6", domain: "Social", project: null, activity: "Hanging out", title: "Cinema — Dune", note: "With Erik & Sofia", start: hm(18, 30), end: hm(21, 0) },
];

export interface RealEntry {
  id: string;
  slot?: string | null;     // the plan id this fills (real sits at that plan's Y)
  off?: boolean;            // off-plan block at its own time
  match?: boolean;          // reality matched the intention
  domain: Domain;
  project?: string | null;
  activity: string;
  title: string;
  note?: string | null;
  start?: number;
  end?: number;
  live?: boolean;
  confidence?: number;
}

// r4 (Formula v3 doc) deliberately omitted — the live check-in fills it.
export const REAL_SEED: RealEntry[] = [
  { id: "r1", slot: "p1", domain: "Health", project: null, activity: "Gym", title: "Strength session", note: "Made it, a touch late", match: true },
  { id: "r2", slot: "p2", domain: "Distraction", project: null, activity: "Scrolling", title: "Fell into TikTok", note: "Opened it “for inspiration” — 1h 50m gone", match: false },
  { id: "r3", slot: "p3", domain: "Work", project: "Litro", activity: "Email", title: "Sent the email", note: "Rushed it out, late", match: true },
  { id: "r5", slot: "p5", domain: "Errands & life admin", project: null, activity: "Errands", title: "Post office run", note: "Returns dropped", match: true },
  { id: "r6", slot: "p6", domain: "Social", project: null, activity: "Hanging out", title: "Cinema — Dune", note: "Worth it", match: true },
  { id: "r7", off: true, domain: "Work", project: "Litro", activity: "Editing", title: "Finished the edit", note: "Finally — after 3pm, like always", start: hm(15, 30), end: hm(17, 30) },
];

export const UPCOMING = [
  { domain: "Errands & life admin" as Domain, title: "Post office + shop", at: "14:00", rel: "in 1h" },
  { domain: "Social" as Domain, title: "Cinema — Dune", at: "18:30", rel: "this evening" },
];

export const DISCREPANCIES = [
  { id: "d1", title: "Read 30 pages — thesis", domain: "Study" as Domain, planned: "planned 3×", last: "last set Tuesday" },
  { id: "d2", title: "Reply to Anna about the collab", domain: "Work" as Domain, planned: "planned twice", last: "from yesterday" },
  { id: "d3", title: "Call the dentist", domain: "Errands & life admin" as Domain, planned: "planned 4 days ago", last: "still waiting" },
];

export const INSIGHT = {
  text: "You’ve planned a morning edit three days running and scrolled instead — but you always finish it after 3pm.",
  nudge: "Want to plan editing for the afternoon?",
};

export const SHORT_TERM_INSIGHTS = [
  { id: "i1", domain: "Errands & life admin" as Domain, metric: "+90 min / day", text: "You systematically underestimate travel and errands by about 90 minutes a day — that’s why your days crack." },
  { id: "i2", domain: "Work" as Domain, metric: "mornings only", text: "Deep work after lunch rarely happens. Your real focus windows are mornings — before 11." },
  { id: "i3", domain: "Work" as Domain, metric: "3 days running", text: "Editing planned for the morning slips every time; it only actually happens after 3pm." },
];

// The block that just ended → drives the auto check-in notification (the slice)
export const JUST_ENDED = { block: "Formula v3 doc", domain: "Work" as Domain, planId: "p4", window: "11:15–12:00", mins: 2 };

export const COACH_ACK = "Got it. Logged on your Real timeline.";

export const SESSION_FEED = {
  due: { id: "s-now", kind: "checkin", block: "Formula v3 doc", domain: "Work" as Domain, window: "11:15–12:00", note: "That block just ended — let’s log what really happened.", mins: 2 },
  upcoming: [
    { id: "s1", kind: "checkin", block: "Post office + shop", domain: "Errands & life admin" as Domain, at: "15:00", rel: "in ~2h", mins: 2 },
    { id: "s2", kind: "checkin", block: "Cinema — Dune", domain: "Social" as Domain, at: "21:00", rel: "tonight", mins: 2 },
  ],
  planning: { id: "s-plan", kind: "planning", at: "21:30", rel: "this evening", note: "Shape tomorrow with Togi — it’ll push for specifics and categorize as you go.", mins: 5 },
  done: [
    { id: "sd1", kind: "checkin", block: "Strength session", domain: "Health" as Domain, at: "08:20", logged: "logged Gym · 38m" },
    { id: "sd2", kind: "morning", block: "Morning plan", domain: "Work" as Domain, at: "07:10", logged: "set 6 intentions" },
  ],
};

export const SUMMARY = { onPlan: 5, total: 7, leakMins: 110, driftMins: 40 };

export const DAY_START = hm(7, 0);
export const DAY_END = hm(21, 30);
export const NOW = hm(13, 5);

export const TogiData = {
  hm, fmt, DOMAINS, DOMAIN_KEYS, domainShort, CATEGORIES, STARTER_ACTIVITIES, PLAN, REAL_SEED,
  UPCOMING, DISCREPANCIES, INSIGHT, SHORT_TERM_INSIGHTS, JUST_ENDED, COACH_ACK, SESSION_FEED,
  SUMMARY, DAY_START, DAY_END, NOW,
};
