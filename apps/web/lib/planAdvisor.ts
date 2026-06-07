/* ============================================================
   Togi — close the loop: use the behavioral memory when planning (spec §1 "Use").
   Given a freshly-categorized plan block + the active insight memory, Togi may
   nudge the block (move it to when it actually happens, pad time you underestimate)
   and explain WHY. Heuristic + explainable; never silent.
   ============================================================ */
import { DAY_END, DAY_START, Domain, PlanBlock, domainShort } from "./data";
import { InsightRecord } from "./insightMemory";

const minutesIn = (s: string) => { const m = s.match(/(\d+)\s*min/i); return m ? parseInt(m[1], 10) : 0; };
const mentions = (s: string, word: string) => s.toLowerCase().includes(word.toLowerCase());

export interface PlanAdvice { block: PlanBlock; reason: string | null; usedInsightIds: string[]; }

export function advisePlan(block: PlanBlock, memory: InsightRecord[]): PlanAdvice {
  let b = { ...block };
  const reasons: string[] = [];
  const used: string[] = [];
  const dur = b.end - b.start;
  const act = (b.activity || "").toLowerCase();
  const domLabel = domainShort(b.domain).toLowerCase();

  // 1) RHYTHM / DRIFT — move the block to when it actually happens
  const rhythm = memory.find((m) =>
    ["rhythm", "drift", "follow_through"].includes(m.family) &&
    (mentions(m.statement, act) || (act === "deep work" && mentions(m.statement, "deep work"))));
  if (rhythm) {
    const txt = rhythm.statement.toLowerCase();
    const wantsAfternoon = /afternoon|after 3|after lunch|3pm|15:/.test(txt) && !/before 11|morning(s)? (only|are)|focus window/.test(txt.replace(/after lunch never|after lunch rarely|after lunch.*(fail|never|rarely)/g, ""));
    const wantsMorning = /morning|before 11/.test(txt) && /(focus|deep work|actually|only)/.test(txt);
    if (wantsAfternoon && b.start < 12 * 60) {
      const start = 15 * 60; b = { ...b, start, end: Math.min(DAY_END, start + dur) };
      reasons.push(`moved it to the afternoon — that's when your ${domLabel === "work" ? act : domLabel} actually happens`); used.push(rhythm.id);
    } else if (wantsMorning && b.start >= 12 * 60) {
      const start = Math.max(DAY_START, 9 * 60); b = { ...b, start, end: start + dur };
      reasons.push(`moved it to the morning — your real focus window`); used.push(rhythm.id);
    }
  }

  // 2) ESTIMATION — pad the time you underestimate
  const est = memory.find((m) => m.family === "estimation" && (mentions(m.statement, domLabel) || mentions(m.statement, act)));
  if (est) {
    const pad = minutesIn(est.metric || "") || minutesIn(est.statement);
    if (pad >= 15) {
      b = { ...b, end: Math.min(DAY_END, b.end + pad) };
      reasons.push(`padded ${pad} min — you usually run over on ${domLabel}`); used.push(est.id);
    }
  }

  const reason = reasons.length ? reasons.join(", and ") : null;
  return { block: b, reason, usedInsightIds: used };
}
