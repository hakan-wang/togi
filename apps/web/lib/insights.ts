/* ============================================================
   Togi — live insight recompute (domain-based, per the categorization spec).
   "An insight updates" after a check-in: derive one banner insight from today's
   Real entries so the banner visibly changes the moment a new entry lands.
   ============================================================ */
import { Domain, DOMAINS, PLAN, RealEntry, SHORT_TERM_INSIGHTS } from "./data";

export interface BannerInsight { domain: Domain; text: string; metric?: string; }

function durationOf(e: RealEntry): number {
  if (e.start != null && e.end != null) return e.end - e.start;
  const p = e.slot ? PLAN.find((x) => x.id === e.slot) : null;
  return p ? p.end - p.start : 0;
}
function fmtDur(min: number) {
  const h = Math.floor(min / 60), m = min % 60;
  return h ? `${h}h${m ? " " + m + "m" : ""}` : `${m}m`;
}

export function computeInsight(real: RealEntry[]): BannerInsight {
  const byDomain: Partial<Record<Domain, number>> = {};
  for (const e of real) byDomain[e.domain] = (byDomain[e.domain] || 0) + durationOf(e);

  const distractionMin = byDomain["Distraction"] || 0;
  if (distractionMin > 0) {
    return {
      domain: "Distraction",
      metric: fmtDur(distractionMin),
      text: `You’ve logged ${fmtDur(distractionMin)} of distraction today — most of it during blocks you’d planned for focus. Awareness comes before change.`,
    };
  }

  const offPlan = real.filter((e) => e.off || e.match === false);
  if (offPlan.length) {
    const e = offPlan[offPlan.length - 1];
    return {
      domain: e.domain,
      metric: "off plan",
      text: `Reality drifted from your plan: ${DOMAINS[e.domain].label} › ${e.activity} wasn’t what you intended. That gap is the data.`,
    };
  }

  const fb = SHORT_TERM_INSIGHTS[0];
  return { domain: fb.domain, metric: fb.metric, text: fb.text };
}
