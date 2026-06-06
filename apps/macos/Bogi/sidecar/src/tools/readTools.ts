import { tool, type StructuredToolInterface } from "@langchain/core/tools";
import { z } from "zod";
import { type DB } from "../db.js";

type OpenDB = () => DB;

function ftsExpr(keywords: string): string {
  const toks = keywords.split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  return toks.map((t) => `"${t}"`).join(" OR ");
}

/// Normalize a range bound for string comparison against ISO datetime rows. A date-only value
/// like "2026-06-06" must cover the whole day: as a start it becomes the day's first instant,
/// as an end the day's last. Without this, end="2026-06-06" sorts BEFORE "2026-06-06T09:00:00Z"
/// and excludes every same-day row. Values that already carry a time are returned unchanged.
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
        const rows = db.prepare(
          `SELECT s.start_at AS start_at, s.category AS category, s.on_task AS on_task, f.description AS description
             FROM segment_fts f JOIN activity_segments s ON s.id = f.segment_id
            WHERE segment_fts MATCH ?
              AND (? IS NULL OR s.start_at >= ?)
              AND (? IS NULL OR s.start_at <= ?)
            ORDER BY s.start_at DESC LIMIT ?`
        ).all(ftsExpr(keywords), lo, lo, hi, hi, limit ?? 20);
        return JSON.stringify({ results: rows });
      } finally { db.close(); }
    },
    {
      name: "search_activity",
      description: "Search the user's recorded activity by keywords, optionally within a time range. Returns matching activity descriptions with their time and on-task status.",
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
          `SELECT minutes, category, on_task FROM activity_segments WHERE start_at >= ? AND start_at <= ?`
        ).all(lo, hi) as { minutes: number; category: string | null; on_task: number | null }[];
        const totalMinutes = segs.reduce((a, s) => a + s.minutes, 0);
        const onTaskMinutes = segs.filter((s) => s.on_task === 1).reduce((a, s) => a + s.minutes, 0);
        const byCat = new Map<string, number>();
        for (const s of segs) byCat.set(s.category ?? "uncategorized", (byCat.get(s.category ?? "uncategorized") ?? 0) + s.minutes);
        const topCategories = [...byCat.entries()]
          .map(([category, minutes]) => ({ category, minutes }))
          .sort((a, b) => b.minutes - a.minutes).slice(0, 8);
        const blocks = db.prepare(
          `SELECT title, start_at, end_at FROM planned_blocks WHERE start_at >= ? AND start_at <= ? ORDER BY start_at`
        ).all(lo, hi);
        return JSON.stringify({ totalMinutes, onTaskMinutes, offTaskMinutes: totalMinutes - onTaskMinutes, topCategories, plannedBlocks: blocks });
      } finally { db.close(); }
    },
    {
      name: "summarize_range",
      description: "Summarize the user's tracked time in a date range: total minutes, on-task vs off-task, top categories, and the calendar blocks they planned.",
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
             FROM activity_segments WHERE start_at >= ? AND start_at <= ?
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

  return [search_activity, summarize_range, list_days, list_goals];
}
