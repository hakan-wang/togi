/* ============================================================
   Togi — live insight recompute.
   The vertical slice requires "an insight updates" after a check-in. This derives
   one short-term banner insight from today's REAL entries, so the moment a new
   entry lands the banner visibly changes.
   ============================================================ */
import { CATEGORIES, CategoryKey, PLAN, RealEntry, SHORT_TERM_INSIGHTS } from "./data";

export interface BannerInsight { cat: CategoryKey; text: string; metric?: string; }

function durationOf(e: RealEntry): number {
  if (e.start != null && e.end != null) return e.end - e.start;
  const p = e.slot ? PLAN.find((x) => x.id === e.slot) : null;
  return p ? p.end - p.start : 0;
}

function fmtDur(min: number) {
  const h = Math.floor(min / 60), m = min % 60;
  return h ? `${h}h${m ? " " + m + "m" : ""}` : `${m}m`;
}

/**
 * Recompute the headline banner insight from the current Real timeline.
 * Order of preference, so a fresh check-in is reflected immediately:
 *  1) Time lost to scrolling today (the product's signature pattern)
 *  2) Off-plan drift (reality didn't match intention)
 *  3) Fall back to the static weekly errand pattern
 */
export function computeInsight(real: RealEntry[]): BannerInsight {
  const minutesByCat: Partial<Record<CategoryKey, number>> = {};
  for (const e of real) minutesByCat[e.cat] = (minutesByCat[e.cat] || 0) + durationOf(e);

  const scrollMin = minutesByCat.scroll || 0;
  if (scrollMin > 0) {
    return {
      cat: "scroll",
      metric: fmtDur(scrollMin),
      text: `You’ve logged ${fmtDur(scrollMin)} of scrolling today — most of it during blocks you’d planned for focus. Awareness comes before change.`,
    };
  }

  const offPlan = real.filter((e) => e.off || e.match === false);
  if (offPlan.length) {
    const e = offPlan[offPlan.length - 1];
    const C = CATEGORIES[e.cat];
    return {
      cat: e.cat,
      metric: "off plan",
      text: `Reality drifted from your plan: ${C.label} › ${e.sub} wasn’t what you intended. That gap is the data.`,
    };
  }

  const fallback = SHORT_TERM_INSIGHTS[0];
  return { cat: fallback.cat, metric: fallback.metric, text: fallback.text };
}
