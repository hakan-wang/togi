/* ============================================================
   Togi — parse a rough time + duration out of a planning utterance so a spoken
   intention becomes a concrete calendar block. Best-effort; if no time is found,
   the planning flow asks the user ("when, and how long?").
   ============================================================ */
import { DAY_START, DAY_END } from "./data";

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
