import { tool, type StructuredToolInterface } from "@langchain/core/tools";
import { z } from "zod";
import { type DB } from "../db.js";

type OpenDB = () => DB;

/// Seconds between raw captures (CaptureController ticks every 6s). Used to estimate minutes
/// from a count of raw observations when no judged segments exist for a range yet.
const CAPTURE_INTERVAL_SEC = 6;
const minutesFromObservations = (count: number): number =>
  Math.round((count * CAPTURE_INTERVAL_SEC) / 6) / 10; // count * 0.1 min, 1 decimal

function ftsExpr(keywords: string): string {
  const toks = keywords.split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  return toks.map((t) => `"${t}"`).join(" OR ");
}

function keywordTokens(keywords: string): string[] {
  return keywords.split(/[^\p{L}\p{N}]+/u).filter(Boolean);
}

/// Normalize a range bound for comparison against stored datetimes. A date-only value like
/// "2026-06-06" must cover the whole day: as a start it becomes the day's first instant, as an
/// end the day's last. Full datetimes pass through unchanged. The SQL wraps both this bound and
/// the stored column in SQLite `datetime()`, which parses ISO "T…Z", space-separated, and
/// date-only forms alike — so a same-day query matches GRDB's space-separated rows (which a
/// raw string compare would wrongly exclude, since ' ' < 'T').
function normalizeBound(value: string | null | undefined, which: "start" | "end"): string | null {
  if (value == null || value === "") return null;
  if (value.length <= 10) return which === "start" ? `${value}T00:00:00.000Z` : `${value}T23:59:59.999Z`;
  return value;
}

export function makeReadTools(open: OpenDB): StructuredToolInterface[] {
  const search_activity = tool(
    async ({ keywords, start, end, limit }) => {
      const db = open();
      try {
        const lo = normalizeBound(start, "start");
        const hi = normalizeBound(end, "end");
        const cap = limit ?? 20;
        const rows = db.prepare(
          `SELECT s.start_at AS start_at, s.cat AS category, s.on_task AS on_task, f.description AS description
             FROM segment_fts f JOIN activity_segments s ON s.id = f.segment_id
            WHERE segment_fts MATCH ?
              AND (? IS NULL OR datetime(s.start_at) >= datetime(?))
              AND (? IS NULL OR datetime(s.start_at) <= datetime(?))
            ORDER BY s.start_at DESC LIMIT ?`
        ).all(ftsExpr(keywords), lo, lo, hi, hi, cap);
        if (rows.length > 0) return JSON.stringify({ source: "segments", results: rows });

        // Fallback: no judged segments matched — search the raw observations the capture loop
        // recorded, so the agent can still answer about recent/just-captured activity.
        const toks = keywordTokens(keywords);
        const like = toks.length
          ? "AND (" + toks.map(() => "(text LIKE ? OR active_app LIKE ? OR active_window_title LIKE ?)").join(" OR ") + ")"
          : "";
        const likeArgs = toks.flatMap((t) => [`%${t}%`, `%${t}%`, `%${t}%`]);
        const obs = db.prepare(
          `SELECT captured_at AS start_at, active_app AS category, active_window_title AS window, text AS description
             FROM activity_observations
            WHERE excluded = 0
              AND (? IS NULL OR datetime(captured_at) >= datetime(?))
              AND (? IS NULL OR datetime(captured_at) <= datetime(?))
              ${like}
            ORDER BY captured_at DESC LIMIT ?`
        ).all(lo, lo, hi, hi, ...likeArgs, cap);
        return JSON.stringify({ source: "observations", results: obs });
      } finally { db.close(); }
    },
    {
      name: "search_activity",
      description: "Search the user's recorded activity by keywords, optionally within a time range. Returns matching activity descriptions with their time and on-task status. Falls back to raw, not-yet-judged observations when no labeled segments match (then `source` is \"observations\").",
      schema: z.object({
        keywords: z.string().describe("Space-separated keywords, e.g. 'video editing'"),
        start: z.string().nullish().describe("ISO-8601 start of range, or omit"),
        end: z.string().nullish().describe("ISO-8601 end of range, or omit"),
        limit: z.number().int().positive().nullish().describe("Max results (default 20)"),
      }),
    }
  );

  const summarize_range = tool(
    async ({ start, end }) => {
      const db = open();
      try {
        const lo = normalizeBound(start, "start");
        const hi = normalizeBound(end, "end");
        const segs = db.prepare(
          `SELECT minutes, cat AS category, on_task FROM activity_segments
            WHERE datetime(start_at) >= datetime(?) AND datetime(start_at) <= datetime(?)`
        ).all(lo, hi) as { minutes: number; category: string | null; on_task: number | null }[];
        const blocks = db.prepare(
          `SELECT title, start_at, end_at FROM planned_blocks
            WHERE datetime(start_at) >= datetime(?) AND datetime(start_at) <= datetime(?) ORDER BY start_at`
        ).all(lo, hi);
        const events = db.prepare(
          `SELECT title, cat, start_at, end_at FROM user_events
            WHERE datetime(start_at) >= datetime(?) AND datetime(start_at) <= datetime(?) ORDER BY start_at`
        ).all(lo, hi);

        if (segs.length === 0) {
          // Fallback: no judged segments yet — estimate from raw observations grouped by app.
          // Minutes are approximate (capture cadence × count); on/off-task is unknown until the
          // judge runs, so it's omitted rather than guessed.
          const obs = db.prepare(
            `SELECT active_app AS app, COUNT(*) AS n FROM activity_observations
              WHERE excluded = 0 AND datetime(captured_at) >= datetime(?) AND datetime(captured_at) <= datetime(?)
              GROUP BY active_app ORDER BY n DESC`
          ).all(lo, hi) as { app: string | null; n: number }[];
          const observationCount = obs.reduce((a, r) => a + r.n, 0);
          const topCategories = obs.slice(0, 8).map((r) => ({
            category: r.app ?? "unknown", minutes: minutesFromObservations(r.n),
          }));
          return JSON.stringify({
            source: "observations",
            estimated: true,
            note: "No judged segments for this range yet; minutes estimated from raw capture, on/off-task unknown.",
            observationCount,
            totalMinutes: minutesFromObservations(observationCount),
            topCategories,
            plannedBlocks: blocks,
            events,
          });
        }

        const totalMinutes = segs.reduce((a, s) => a + s.minutes, 0);
        const onTaskMinutes = segs.filter((s) => s.on_task === 1).reduce((a, s) => a + s.minutes, 0);
        const byCat = new Map<string, number>();
        for (const s of segs) byCat.set(s.category ?? "uncategorized", (byCat.get(s.category ?? "uncategorized") ?? 0) + s.minutes);
        const topCategories = [...byCat.entries()]
          .map(([category, minutes]) => ({ category, minutes }))
          .sort((a, b) => b.minutes - a.minutes).slice(0, 8);
        return JSON.stringify({ source: "segments", totalMinutes, onTaskMinutes, offTaskMinutes: totalMinutes - onTaskMinutes, topCategories, plannedBlocks: blocks, events });
      } finally { db.close(); }
    },
    {
      name: "summarize_range",
      description: "Summarize the user's tracked time in a date range: total minutes, on-task vs off-task, top categories, and the calendar blocks they planned. Falls back to an estimate from raw, not-yet-judged observations when no labeled segments exist (then `source` is \"observations\" and minutes are approximate).",
      schema: z.object({
        start: z.string().describe("ISO-8601 start of range"),
        end: z.string().describe("ISO-8601 end of range"),
      }),
    }
  );

  const list_days = tool(
    async ({ start, end }) => {
      const db = open();
      try {
        const lo = normalizeBound(start, "start");
        const hi = normalizeBound(end, "end");
        const rows = db.prepare(
          `SELECT substr(start_at,1,10) AS date,
                  SUM(minutes) AS totalMinutes,
                  SUM(CASE WHEN on_task = 1 THEN minutes ELSE 0 END) AS onTaskMinutes
             FROM activity_segments
            WHERE datetime(start_at) >= datetime(?) AND datetime(start_at) <= datetime(?)
            GROUP BY date ORDER BY date`
        ).all(lo, hi);
        return JSON.stringify({ days: rows });
      } finally { db.close(); }
    },
    {
      name: "list_days",
      description: "List per-day total and on-task minutes across a date range. Use for trend questions like 'which day last week was most productive'.",
      schema: z.object({
        start: z.string().describe("ISO-8601 start of range"),
        end: z.string().describe("ISO-8601 end of range"),
      }),
    }
  );

  const list_goals = tool(
    async () => {
      const db = open();
      try {
        const rows = db.prepare(`SELECT title, period, target FROM goals ORDER BY created_at`).all();
        return JSON.stringify({ goals: rows });
      } finally { db.close(); }
    },
    {
      name: "list_goals",
      description: "List the user's active goals and their targets so you can reason about progress.",
      schema: z.object({}),
    }
  );

  const list_categories = tool(
    async () => {
      const db = open();
      try {
        const rows = db.prepare(
          `SELECT id, name, color, description FROM category_registry ORDER BY sort_order`
        ).all();
        return JSON.stringify({ categories: rows });
      } finally { db.close(); }
    },
    {
      name: "list_categories",
      description: "List the user's current categories (id, name, color). Call this before labeling activity so you reuse an existing category when one fits.",
      schema: z.object({}),
    }
  );

  const read_behaviour = tool(
    async () => {
      const db = open();
      try {
        const get = (k: string) => (db.prepare(`SELECT value FROM settings WHERE key = ?`).get(k) as any)?.value ?? null;
        return JSON.stringify({
          name: get("user_display_name"),
          northStar: get("north_star"),
          northStarWhy: get("north_star_why"),
          behaviour: get("behaviour_profile"),
        });
      } finally { db.close(); }
    },
    {
      name: "read_behaviour",
      description: "Recall what you know about the user: their name, their north-star goal (and why), and the behaviour patterns you have learned. Call before judging activity or answering questions about their habits.",
      schema: z.object({}),
    }
  );

  const list_events = tool(
    async ({ start, end }) => {
      const db = open();
      try {
        const lo = normalizeBound(start, "start");
        const hi = normalizeBound(end, "end");
        const rows = db.prepare(
          `SELECT id, title, desc, cat, sub, start_at, end_at FROM user_events
            WHERE datetime(start_at) >= datetime(?) AND datetime(start_at) <= datetime(?)
            ORDER BY start_at`
        ).all(lo, hi);
        return JSON.stringify({ events: rows });
      } finally { db.close(); }
    },
    {
      name: "list_events",
      description: "List the user's real-world commitments (gym, meetings, appointments) in a date range.",
      schema: z.object({ start: z.string(), end: z.string() }),
    }
  );

  return [search_activity, summarize_range, list_days, list_goals, list_categories, read_behaviour, list_events];
}
