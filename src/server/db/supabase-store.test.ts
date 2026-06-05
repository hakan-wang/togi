import { describe, expect, it } from "vitest";
import type { AgentRun } from "@/server/schemas/agents";
import type { Goal } from "@/server/schemas/goals";
import type { PlannedBlock } from "@/server/schemas/planned-blocks";
import type { RealityLog } from "@/server/schemas/reality-logs";
import { mapAgentRunRow, mapGoalRow, mapPlannedBlockRow, mapRealityLogRow, shouldUseSupabaseStore } from "./supabase-store";

describe("supabase store", () => {
  it("uses Supabase store only when both Supabase credentials exist", () => {
    expect(shouldUseSupabaseStore({ SUPABASE_URL: "https://example.supabase.co", SUPABASE_SERVICE_ROLE_KEY: "secret" })).toBe(true);
    expect(shouldUseSupabaseStore({ SUPABASE_URL: "https://example.supabase.co" })).toBe(false);
  });

  it("maps snake_case goal rows to service contracts", () => {
    const goal: Goal = mapGoalRow({
      id: "00000000-0000-4000-8000-000000000001",
      user_id: "user-1",
      title: "Ship backend",
      description: null,
      status: "active",
      created_at: "2026-06-05T09:00:00.000Z",
      updated_at: "2026-06-05T09:00:00.000Z"
    });

    expect(goal).toMatchObject({ userId: "user-1", createdAt: "2026-06-05T09:00:00.000Z" });
  });

  it("maps planned block JSON success criteria", () => {
    const block: PlannedBlock = mapPlannedBlockRow({
      id: "00000000-0000-4000-8000-000000000002",
      user_id: "user-1",
      calendar_event_id: "event-1",
      title: "Draft plan",
      start_time: "2026-06-05T09:00:00.000Z",
      end_time: "2026-06-05T10:00:00.000Z",
      intention_text: "Draft plan",
      success_criteria: ["Write plan"],
      category: "planning",
      status: "planned",
      created_by: "user",
      created_at: "2026-06-05T09:00:00.000Z",
      updated_at: "2026-06-05T09:00:00.000Z"
    });

    expect(block.successCriteria).toEqual(["Write plan"]);
    expect(block.calendarEventId).toBe("event-1");
  });

  it("maps reality log category JSON and agent run audit fields", () => {
    const log: RealityLog = mapRealityLogRow({
      id: "00000000-0000-4000-8000-000000000003",
      user_id: "user-1",
      planned_block_id: "00000000-0000-4000-8000-000000000002",
      actual_summary: "Wrote plan.",
      completion_score: 1,
      deviation_reason: "",
      actual_categories_json: ["planning"],
      confirmed_by_user: true,
      source: "user",
      created_at: "2026-06-05T09:00:00.000Z",
      updated_at: "2026-06-05T09:00:00.000Z"
    });
    const run: AgentRun = mapAgentRunRow({
      id: "00000000-0000-4000-8000-000000000004",
      user_id: "user-1",
      agent_name: "planner",
      input_json: { request: "plan" },
      output_json: { blocks: [] },
      status: "completed",
      error: null,
      model: "gpt-4.1-mini",
      started_at: "2026-06-05T09:00:00.000Z",
      completed_at: "2026-06-05T09:01:00.000Z"
    });

    expect(log.actualCategories).toEqual(["planning"]);
    expect(run.inputJson).toEqual({ request: "plan" });
  });
});
