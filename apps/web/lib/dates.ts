/* ============================================================
   Togi — real date/time helpers so the calendar reflects the actual day & clock.
   A "day key" is YYYY-MM-DD in local time. Minutes are minutes-from-local-midnight.
   ============================================================ */
export function dayKey(d: Date = new Date()): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
export function nowMinutes(d: Date = new Date()): number { return d.getHours() * 60 + d.getMinutes(); }

export interface WeekDay { key: string; dow: string; n: number; isToday: boolean; isPast: boolean; isFuture: boolean; }

/** A rolling 7-day strip: 3 days back → today → 3 forward, so you can review the
   past AND plan ahead. Real dates + correct weekday names. */
export function weekDays(): WeekDay[] {
  const names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const today0 = new Date(); today0.setHours(0, 0, 0, 0);
  const tk = dayKey(today0);
  const out: WeekDay[] = [];
  for (let i = -3; i <= 3; i++) {
    const dd = new Date(today0); dd.setDate(today0.getDate() + i);
    out.push({ key: dayKey(dd), dow: names[dd.getDay()], n: dd.getDate(), isToday: i === 0, isPast: i < 0, isFuture: i > 0 });
  }
  return out;
}

/** "Sunday · 7 June" style label for a day key. Falls back to today if missing. */
export function dayLabel(key?: string): string {
  const k = key || dayKey();
  const [y, m, d] = k.split("-").map(Number);
  const dt = new Date(y, m - 1, d);
  return dt.toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" });
}

/** Build an ISO timestamp for a given day key + minutes-of-day (local). */
export function isoFromDayMin(dayK: string, minutes: number): string {
  const [y, m, d] = dayK.split("-").map(Number);
  return new Date(y, m - 1, d, Math.floor(minutes / 60), minutes % 60, 0, 0).toISOString();
}

/** Does a block belong to the given day? Undated seed blocks count as "today". */
export function onDay(block: { date?: string }, key: string, todayK: string): boolean {
  return (block.date || todayK) === key;
}
