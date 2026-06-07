/* ============================================================
   Togi — "memory about the user": stable FACTS (not patterns), e.g. when the user
   usually wakes. Planning respects these (never schedule before wake time).
   Learned from history with a sensible default; persisted locally (Supabase later).
   ============================================================ */
import { seedHistory } from "./behavior";

export interface UserFacts { wakeMin: number; sleepMin: number; planningMin: number; }
const LS = "togi.facts.v1";
const DEFAULTS: UserFacts = { wakeMin: 7 * 60, sleepMin: 23 * 60, planningMin: 21 * 60 };

/** Learn the usual wake time from the earliest real activity across history. */
function learnWake(): number {
  let earliest = 24 * 60;
  for (const d of seedHistory()) for (const r of d.real) earliest = Math.min(earliest, r.start);
  if (earliest >= 24 * 60) return DEFAULTS.wakeMin;
  return Math.max(5 * 60, Math.floor(earliest / 30) * 30); // round down to the half hour
}

export function loadFacts(): UserFacts {
  if (typeof window === "undefined") return DEFAULTS;
  try {
    const saved = JSON.parse(window.localStorage.getItem(LS) || "null");
    if (saved && typeof saved.wakeMin === "number") return { ...DEFAULTS, ...saved };
  } catch { /* ignore */ }
  const facts: UserFacts = { ...DEFAULTS, wakeMin: learnWake() };
  try { window.localStorage.setItem(LS, JSON.stringify(facts)); } catch { /* ignore */ }
  return facts;
}

export function setFact<K extends keyof UserFacts>(key: K, value: UserFacts[K]) {
  const f = loadFacts(); f[key] = value;
  try { window.localStorage.setItem(LS, JSON.stringify(f)); } catch { /* ignore */ }
}
