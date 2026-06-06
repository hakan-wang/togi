/* ============================================================
   Togi — demo day data (ported from the Claude Design prototype's data.js).
   One honest Thursday for Håkan: the gap between plan & reality.
   Times are minutes from midnight.

   NOTE vs the prototype: the "Formula v3 doc" real block (old r4) is intentionally
   REMOVED from the seed. That is the block the live vertical-slice check-in fills —
   so when you speak your check-in, you literally watch it land on the Real timeline.
   ============================================================ */

export const hm = (h: number, m = 0) => h * 60 + m;

export function fmt(min: number) {
  const h = Math.floor(min / 60), m = min % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

export type CategoryKey =
  | "deepwork" | "creative" | "admin" | "health" | "social"
  | "errands" | "leisure" | "scroll" | "personal";

export interface Category { key: CategoryKey; label: string; color: string; tint: string; }

export const CATEGORIES: Record<CategoryKey, Category> = {
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

export const CATEGORY_KEYS = Object.keys(CATEGORIES) as CategoryKey[];

export interface PlanBlock {
  id: string; cat: CategoryKey; sub: string; title: string; desc: string; start: number; end: number;
}

// ---- PLAN : the intentions, set last night. Deliberate empty gap 12:00–14:00. ----
export const PLAN: PlanBlock[] = [
  { id: "p1", cat: "health", sub: "Gym", title: "Strength session", desc: "Push day", start: hm(7, 30), end: hm(8, 15) },
  { id: "p2", cat: "creative", sub: "Editing", title: "Edit launch vlog", desc: "Cut the Litro launch video", start: hm(8, 30), end: hm(10, 30) },
  { id: "p3", cat: "admin", sub: "Suppliers", title: "Email co-manufacturers", desc: "Chase the sample timeline", start: hm(10, 30), end: hm(11, 15) },
  { id: "p4", cat: "deepwork", sub: "Litro", title: "Formula v3 doc", desc: "Finish the write-up", start: hm(11, 15), end: hm(12, 0) },
  /* 12:00–14:00 : intentionally empty — tap to self check-in */
  { id: "p5", cat: "errands", sub: "Town", title: "Post office + shop", desc: "Drop the returns", start: hm(14, 0), end: hm(15, 0) },
  { id: "p6", cat: "social", sub: "Friends", title: "Cinema — Dune", desc: "With Erik & Sofia", start: hm(18, 30), end: hm(21, 0) },
];

export interface RealEntry {
  id: string;
  slot?: string | null;     // the plan id this fills (real sits at that plan's Y)
  off?: boolean;            // off-plan block at its own time, nothing planned behind it
  match?: boolean;          // reality matched the intention
  cat: CategoryKey;
  sub: string;
  title: string;
  desc: string;
  start?: number;           // only for off-plan
  end?: number;
  live?: boolean;           // added this session via a real check-in
}

// ---- REAL : what really happened (seed). r4 / Formula v3 doc deliberately omitted. ----
export const REAL_SEED: RealEntry[] = [
  { id: "r1", slot: "p1", cat: "health", sub: "Gym", title: "Strength session", desc: "Made it, a touch late", match: true },
  { id: "r2", slot: "p2", cat: "scroll", sub: "TikTok", title: "Fell into TikTok", desc: "Opened it “for inspiration” — 1h 50m gone", match: false },
  { id: "r3", slot: "p3", cat: "admin", sub: "Suppliers", title: "Sent the email", desc: "Rushed it out, late", match: true },
  { id: "r5", slot: "p5", cat: "errands", sub: "Town", title: "Post office run", desc: "Returns dropped", match: true },
  { id: "r6", slot: "p6", cat: "social", sub: "Friends", title: "Cinema — Dune", desc: "Worth it", match: true },
  { id: "r7", off: true, cat: "creative", sub: "Editing", title: "Finished the edit", desc: "Finally — after 3pm, like always", start: hm(15, 30), end: hm(17, 30) },
];

export const UPCOMING = [
  { cat: "errands" as CategoryKey, title: "Post office + shop", at: "14:00", rel: "in 1h" },
  { cat: "social" as CategoryKey, title: "Cinema — Dune", at: "18:30", rel: "this evening" },
];

export const DISCREPANCIES = [
  { id: "d1", title: "Read 30 pages — thesis", cat: "deepwork" as CategoryKey, planned: "planned 3×", last: "last set Tuesday" },
  { id: "d2", title: "Reply to Anna about the collab", cat: "admin" as CategoryKey, planned: "planned twice", last: "from yesterday" },
  { id: "d3", title: "Call the dentist", cat: "personal" as CategoryKey, planned: "planned 4 days ago", last: "still waiting" },
];

export const INSIGHT = {
  text: "You’ve planned a morning edit three days running and scrolled instead — but you always finish it after 3pm.",
  nudge: "Want to plan editing for the afternoon?",
};

export const SHORT_TERM_INSIGHTS = [
  { id: "p1", cat: "errands" as CategoryKey, metric: "+90 min / day", text: "You systematically underestimate travel and errands by about 90 minutes a day — that’s why your days crack." },
  { id: "p2", cat: "deepwork" as CategoryKey, metric: "mornings only", text: "Deep work after lunch rarely happens. Your real focus windows are mornings — before 11." },
  { id: "p3", cat: "creative" as CategoryKey, metric: "3 days running", text: "Editing planned for the morning slips every time; it only actually happens after 3pm." },
];

// ---- The block that just ended → drives the auto check-in notification (the slice) ----
export const JUST_ENDED = { block: "Formula v3 doc", cat: "deepwork" as CategoryKey, planId: "p4", window: "11:15–12:00", mins: 2 };

export const COACH_ACK = "Got it. Logged on your Real timeline.";

export const SESSION_FEED = {
  due: { id: "s-now", kind: "checkin", block: "Formula v3 doc", cat: "deepwork" as CategoryKey, window: "11:15–12:00", note: "That block just ended — let’s log what really happened.", mins: 2 },
  upcoming: [
    { id: "s1", kind: "checkin", block: "Post office + shop", cat: "errands" as CategoryKey, at: "15:00", rel: "in ~2h", mins: 2 },
    { id: "s2", kind: "checkin", block: "Cinema — Dune", cat: "social" as CategoryKey, at: "21:00", rel: "tonight", mins: 2 },
  ],
  planning: { id: "s-plan", kind: "planning", at: "21:30", rel: "this evening", note: "Shape tomorrow with Togi — it’ll push for specifics and categorize as you go.", mins: 5 },
  done: [
    { id: "d1", kind: "checkin", block: "Strength session", cat: "health" as CategoryKey, at: "08:20", logged: "logged Gym · 38m" },
    { id: "d2", kind: "morning", block: "Morning plan", cat: "deepwork" as CategoryKey, at: "07:10", logged: "set 6 intentions" },
  ],
};

export const SUMMARY = { onPlan: 5, total: 7, leakMins: 110, driftMins: 40 };

export const DAY_START = hm(7, 0);
export const DAY_END = hm(21, 30);
export const NOW = hm(13, 5); // demo "now" on this Thursday

// Convenience grouped export (mirrors the prototype's window.TogiData)
export const TogiData = {
  hm, fmt, CATEGORIES, CATEGORY_KEYS, PLAN, REAL_SEED, UPCOMING, DISCREPANCIES,
  INSIGHT, SHORT_TERM_INSIGHTS, JUST_ENDED, COACH_ACK, SESSION_FEED, SUMMARY,
  DAY_START, DAY_END, NOW,
};
