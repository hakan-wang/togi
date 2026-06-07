/* ============================================================
   Togi — parse a rough time + duration out of a planning utterance so a spoken
   intention becomes a concrete calendar block. Best-effort; if no time is found,
   the planning flow asks the user ("when, and how long?").
   ============================================================ */
import { DAY_START, DAY_END, Domain } from "./data";

/** Minutes of duration mentioned in text ("2 hours", "45 min"), or null. */
export function parseDuration(text: string): number | null {
  const h = text.match(/(\d+(?:\.\d+)?)\s*(h\b|hour|hr|tim)/i);
  const m = text.match(/(\d+)\s*(m\b|min)/i);
  let mins = 0;
  if (h) mins += Math.round(parseFloat(h[1]) * 60);
  if (m) mins += parseInt(m[1], 10);
  return mins || null;
}

/** Light, local domain/activity guess for a PLANNED block (no LLM — plans aren't
   force-categorized; only real check-ins get the full categorizer). */
export function guessPlanMeta(text: string): { domain: Domain; activity: string } {
  const KW: Array<[RegExp, Domain, string]> = [
    [/gym|run|workout|train|lift|yoga|walk|sport|padel/i, "Health", "Gym"],
    [/edit|vlog|film|render|footage/i, "Work", "Editing"],
    [/email|mail|inbox|supplier|reply/i, "Work", "Email"],
    [/writ|doc|formula|draft|essay|report/i, "Work", "Writing"],
    [/meet|call|standup|sync/i, "Work", "Meeting"],
    [/stud|exam|homework|revis|lecture|class|read/i, "Study", "Studying"],
    [/clean|laundry|dishes|errand|shop|grocery|post office|bank|pickup/i, "Errands & life admin", "Errands"],
    [/friend|dinner|cinema|party|hang|family|date|concert|visit/i, "Social", "Hanging out"],
    [/game|movie|relax|rest|hobby/i, "Leisure", "Resting"],
  ];
  for (const [re, d, a] of KW) if (re.test(text)) return { domain: d, activity: a };
  return { domain: "Work", activity: "Planned" };
}

/** A short, clean block title from a spoken intention (strips the time phrases). */
export function cleanTitle(text: string): string {
  let t = text
    .replace(/\bat\s+\d{1,2}([:.]\d{2})?\s*(am|pm)?\b/gi, " ")
    .replace(/\bfor\s+\d+(?:\.\d+)?\s*(h\b|hours?|hrs?|min(ute)?s?)\b/gi, " ")
    .replace(/\b(tomorrow|today|tonight|this (morning|afternoon|evening)|in the (morning|afternoon|evening)|(early )?morning|afternoon|evening|noon)\b/gi, " ")
    .replace(/\bfor\s+\d+\b/gi, " ")
    .replace(/\s+/g, " ").trim();
  if (!t) t = text.trim();
  return t.charAt(0).toUpperCase() + t.slice(1, 60);
}

const PARTS: Array<[RegExp, number]> = [
  [/\bearly morning\b/i, 7 * 60],
  [/\bmorning\b/i, 9 * 60],
  [/\b(forenoon|before lunch)\b/i, 10 * 60],
  [/\b(noon|lunch)\b/i, 12 * 60],
  [/\b(afternoon|after lunch)\b/i, 14 * 60],
  [/\b(late afternoon)\b/i, 16 * 60],
  [/\b(evening)\b/i, 19 * 60],
  [/\b(tonight|night)\b/i, 20 * 60],
];

function parseStart(text: string): number | null {
  // explicit clock: "at 3pm", "3 pm", "15:00", "at 15", "9.30"
  const ampm = text.match(/\b(?:at\s*)?(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)\b/i);
  if (ampm) {
    let h = parseInt(ampm[1], 10) % 12;
    if (/pm/i.test(ampm[3])) h += 12;
    return h * 60 + (ampm[2] ? parseInt(ampm[2], 10) : 0);
  }
  const h24 = text.match(/\b(?:at\s*)(\d{1,2})(?:[:.](\d{2}))?\b/);
  if (h24) { const h = parseInt(h24[1], 10); if (h >= 0 && h <= 23) return h * 60 + (h24[2] ? parseInt(h24[2], 10) : 0); }
  const colon = text.match(/\b(\d{1,2}):(\d{2})\b/);
  if (colon) return parseInt(colon[1], 10) * 60 + parseInt(colon[2], 10);
  for (const [re, m] of PARTS) if (re.test(text)) return m;
  return null;
}

/** Returns {start,end} minutes-of-day, or null if no time could be inferred. */
export function parseTimeRange(text: string, durationMin?: number | null): { start: number; end: number } | null {
  const start = parseStart(text);
  if (start == null) return null;
  const dur = durationMin && durationMin > 0 ? durationMin : 60;
  const s = Math.max(DAY_START, Math.min(start, DAY_END - 15));
  const e = Math.min(DAY_END, s + dur);
  return { start: s, end: e };
}
