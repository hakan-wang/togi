import { describe, expect, it } from "vitest";
import { getSummaryTable, mapStoredSummary, mapSummaryUpsert, upsertStoredSummary } from "@/lib/db/bogi-store";

function fakeSummaryClient() {
  const calls: unknown[] = [];
  return {
    calls,
    from(table: string) {
      calls.push({ table, op: "from" });
      return {
        upsert(value: Record<string, unknown>, options: Record<string, unknown>) {
          calls.push({ table, op: "upsert", value, options });
          return {
            select(columns: string) {
              calls.push({ table, op: "select", columns });
              return {
                async single() {
                  return { data: { id: "sum_1" }, error: null };
                }
              };
            }
          };
        }
      };
    }
  };
}

describe("summary store helpers", () => {
  it("maps scopes to summary tables", () => {
    expect(getSummaryTable("day")).toEqual({ table: "daily_summaries", dateColumn: "day" });
    expect(getSummaryTable("week")).toEqual({ table: "weekly_summaries", dateColumn: "week_start" });
    expect(getSummaryTable("month")).toEqual({ table: "monthly_summaries", dateColumn: "month_start" });
  });

  it("maps stored summary rows to API shape", () => {
    expect(mapStoredSummary("month", {
      summary: "June had better lock-in completion.",
      stats_json: { plannedMinutes: 600, confirmedRealityMinutes: 480, gapMinutes: 120 }
    })).toEqual({
      scope: "month",
      summary: "June had better lock-in completion.",
      stats: { plannedMinutes: 600, confirmedRealityMinutes: 480, gapMinutes: 120 }
    });
  });

  it("maps summary upserts to scope-specific date columns", () => {
    expect(mapSummaryUpsert({
      userId: "usr_1",
      scope: "week",
      date: "2026-06-01",
      summary: "Week summary.",
      stats: { plannedMinutes: 240 }
    })).toEqual({
      table: "weekly_summaries",
      value: {
        user_id: "usr_1",
        week_start: "2026-06-01",
        summary: "Week summary.",
        stats_json: { plannedMinutes: 240 }
      },
      conflict: "user_id,week_start"
    });
  });

  it("upserts stored summaries", async () => {
    const client = fakeSummaryClient();
    const saved = await upsertStoredSummary(client, {
      userId: "usr_1",
      scope: "day",
      date: "2026-06-06",
      summary: "Day summary.",
      stats: { gapMinutes: 20 }
    });

    expect(saved).toEqual({ id: "sum_1" });
    expect(client.calls).toContainEqual({
      table: "daily_summaries",
      op: "upsert",
      value: {
        user_id: "usr_1",
        day: "2026-06-06",
        summary: "Day summary.",
        stats_json: { gapMinutes: 20 }
      },
      options: { onConflict: "user_id,day" }
    });
  });
});
