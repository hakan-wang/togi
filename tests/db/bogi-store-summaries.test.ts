import { describe, expect, it } from "vitest";
import { getSummaryTable, mapStoredSummary } from "@/lib/db/bogi-store";

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
});
