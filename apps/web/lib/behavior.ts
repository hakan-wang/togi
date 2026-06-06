/* ============================================================
   Togi — behavioral stats engine (per togi_insights_spec.md §7).
   Code crunches ~2-3 weeks of plan vs real into clean FACTS per insight family;
   the AI (in /api/insights) turns these into human insights. Evidence floors here
   are the Miss Test in code: a pattern must span ≥2 days / ≥3 instances to count.

   For the demo we seed realistic history embodying the patterns; real users get the
   same engine run over their accumulating data.
   ============================================================ */
import { Domain, RealEntry } from "./data";

const hm = (h: number, m = 0) => h * 60 + m;

interface DayBlock { domain: Domain; activity: string; project?: string | null; start: number; end: number; planId?: string; }
interface Day { offset: number; plan: DayBlock[]; real: (DayBlock & { slot?: string; matched: boolean })[]; }

/* ---- Seed ~14 days that embody the patterns (deterministic by day index) ---- */
export function seedHistory(days = 14): Day[] {
  const out: Day[] = [];
  for (let i = 0; i < days; i++) {
    const plan: DayBlock[] = [
      { domain: "Health", activity: "Gym", start: hm(7, 30), end: hm(8, 15), planId: "g" },
      { domain: "Work", activity: "Editing", project: "Litro", start: hm(8, 30), end: hm(10, 30), planId: "ed" },
      { domain: "Work", activity: "Email", project: "Litro", start: hm(10, 30), end: hm(11, 15), planId: "em" },
      { domain: "Work", activity: "Deep work", start: hm(13, 0), end: hm(15, 0), planId: "dw" }, // planned after lunch
      { domain: "Errands & life admin", activity: "Errands", start: hm(15, 0), end: hm(16, 0), planId: "er" },
      { domain: "Social", activity: "Hanging out", start: hm(18, 30), end: hm(21, 0), planId: "so" },
    ];
    const real: Day["real"] = [];
    real.push({ domain: "Health", activity: "Gym", start: hm(7, 35), end: hm(8, 15), slot: "g", matched: true });
    // editing slips ~5 of 7 days: scroll in the morning, edit moves to afternoon
    const slips = i % 7 !== 3 && i % 7 !== 6;
    if (slips) {
      real.push({ domain: "Distraction", activity: "Scrolling", start: hm(8, 40), end: hm(10, 25), slot: "ed", matched: false });
      real.push({ domain: "Work", activity: "Editing", project: "Litro", start: hm(15, 10), end: hm(17, 0), matched: false });
    } else {
      real.push({ domain: "Work", activity: "Editing", project: "Litro", start: hm(8, 35), end: hm(10, 30), slot: "ed", matched: true });
    }
    real.push({ domain: "Work", activity: "Email", project: "Litro", start: hm(10, 35), end: hm(11, 20), slot: "em", matched: true });
    // deep work after lunch basically never happens
    if (i % 7 === 5) real.push({ domain: "Work", activity: "Deep work", start: hm(13, 10), end: hm(14, 0), slot: "dw", matched: true });
    else real.push({ domain: "Distraction", activity: "Scrolling", start: hm(13, 0), end: hm(13, 50), slot: "dw", matched: false });
    // errands run long (+60–110 min)
    const overrun = 60 + (i % 4) * 15;
    real.push({ domain: "Errands & life admin", activity: "Errands", start: hm(15, 0), end: hm(16, 0) + overrun, slot: "er", matched: true });
    real.push({ domain: "Social", activity: "Hanging out", start: hm(18, 40), end: hm(21, 0), slot: "so", matched: true });
    out.push({ offset: i, plan, real });
  }
  return out;
}

export interface Stats {
  days: number;
  followThroughPct: number;
  slips: { activity: string; plannedDays: number; slippedDays: number; movesToAfterHour?: number }[];
  estimation: { domain: string; avgOverrunMin: number; days: number }[];
  distraction: { duringActivity: string; avgMinPerDay: number; days: number; peakHour: number }[];
  focus: { activity: string; window: string; days: number }[];
}

const dur = (b: { start: number; end: number }) => b.end - b.start;
const hourOf = (m: number) => Math.floor(m / 60);

/** Aggregate history (+ today's live entries) into facts. Evidence floors applied. */
export function computeStats(history: Day[], liveReal: RealEntry[] = []): Stats {
  const days = history.length;
  // follow-through: planned blocks that matched
  let planned = 0, matched = 0;
  history.forEach((d) => d.plan.forEach((p) => { planned++; if (d.real.some((r) => r.slot === p.planId && r.matched)) matched++; }));

  // slips by planned activity
  const slipMap: Record<string, { plannedDays: number; slippedDays: number; afterHours: number[] }> = {};
  history.forEach((d) => d.plan.forEach((p) => {
    const k = p.activity; slipMap[k] = slipMap[k] || { plannedDays: 0, slippedDays: 0, afterHours: [] };
    slipMap[k].plannedDays++;
    const did = d.real.some((r) => r.slot === p.planId && r.matched);
    if (!did) {
      slipMap[k].slippedDays++;
      const moved = d.real.find((r) => r.activity === p.activity && !r.slot);
      if (moved) slipMap[k].afterHours.push(hourOf(moved.start));
    }
  }));
  const slips = Object.entries(slipMap)
    .filter(([, v]) => v.slippedDays >= 2)
    .map(([activity, v]) => ({ activity, plannedDays: v.plannedDays, slippedDays: v.slippedDays, movesToAfterHour: v.afterHours.length ? Math.min(...v.afterHours) : undefined }));

  // estimation overrun by domain (actual - planned, on matched blocks)
  const estMap: Record<string, { total: number; n: number }> = {};
  history.forEach((d) => d.plan.forEach((p) => {
    const r = d.real.find((x) => x.slot === p.planId && x.matched);
    if (r) { const delta = dur(r) - dur(p); estMap[p.domain] = estMap[p.domain] || { total: 0, n: 0 }; estMap[p.domain].total += delta; estMap[p.domain].n++; }
  }));
  const estimation = Object.entries(estMap)
    .map(([domain, v]) => ({ domain, avgOverrunMin: Math.round(v.total / v.n), days: v.n }))
    .filter((e) => Math.abs(e.avgOverrunMin) >= 20 && e.days >= 3);

  // distraction co-occurrence: distraction blocks that fill a planned non-distraction slot
  const distMap: Record<string, { mins: number; days: Set<number>; hours: number[] }> = {};
  history.forEach((d) => d.real.forEach((r) => {
    if (r.domain === "Distraction" && r.slot) {
      const p = d.plan.find((x) => x.planId === r.slot);
      const key = p ? p.activity : "unplanned";
      distMap[key] = distMap[key] || { mins: 0, days: new Set(), hours: [] };
      distMap[key].mins += dur(r); distMap[key].days.add(d.offset); distMap[key].hours.push(hourOf(r.start));
    }
  }));
  const distraction = Object.entries(distMap)
    .filter(([, v]) => v.days.size >= 2)
    .map(([duringActivity, v]) => ({ duringActivity, avgMinPerDay: Math.round(v.mins / v.days.size), days: v.days.size, peakHour: mode(v.hours) }));

  // focus windows: when deep work / editing actually happened (matched or moved)
  const focusMap: Record<string, number[]> = {};
  history.forEach((d) => d.real.forEach((r) => {
    if ((r.activity === "Deep work" || r.activity === "Editing")) { focusMap[r.activity] = focusMap[r.activity] || []; focusMap[r.activity].push(hourOf(r.start)); }
  }));
  const focus = Object.entries(focusMap)
    .filter(([, hrs]) => hrs.length >= 3)
    .map(([activity, hrs]) => ({ activity, window: windowLabel(hrs), days: hrs.length }));

  return { days, followThroughPct: planned ? Math.round((matched / planned) * 100) : 0, slips, estimation, distraction, focus };
}

function mode(arr: number[]): number { const c: Record<number, number> = {}; let best = arr[0], n = 0; for (const x of arr) { c[x] = (c[x] || 0) + 1; if (c[x] > n) { n = c[x]; best = x; } } return best; }
function windowLabel(hours: number[]): string {
  const before11 = hours.filter((h) => h < 11).length, after15 = hours.filter((h) => h >= 15).length;
  if (before11 >= hours.length * 0.6) return "mornings (before 11)";
  if (after15 >= hours.length * 0.6) return "afternoons (after 3pm)";
  return "scattered";
}
