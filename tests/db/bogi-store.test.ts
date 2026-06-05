import { describe, expect, it } from "vitest";
import {
  deleteUserData,
  exportUserData,
  mapRealityLogInsert,
  mapScreenFrameBatchInsert
} from "@/lib/db/bogi-store";
import type { RealityLogInput } from "@/lib/zod/contracts";

class QueryBuilder {
  constructor(private table: string, private calls: unknown[]) {}

  select(columns = "*") {
    this.calls.push({ table: this.table, op: "select", columns });
    return this;
  }

  eq(column: string, value: string) {
    this.calls.push({ table: this.table, op: "eq", column, value });
    return { data: [{ table: this.table, user_id: value }], error: null };
  }

  delete() {
    this.calls.push({ table: this.table, op: "delete" });
    return this;
  }
}

function fakeClient() {
  const calls: unknown[] = [];
  return {
    calls,
    from(table: string) {
      calls.push({ table, op: "from" });
      return new QueryBuilder(table, calls);
    }
  };
}

describe("bogi store", () => {
  it("exports user-owned Bogi data collections", async () => {
    const client = fakeClient();
    const data = await exportUserData(client, "usr_1");

    expect(Object.keys(data)).toEqual([
      "plannedBlocks",
      "realityLogs",
      "screenObservationSummaries",
      "dailySummaries",
      "weeklySummaries",
      "monthlySummaries",
      "userPatterns"
    ]);
    expect(client.calls).toContainEqual({ table: "planned_blocks", op: "eq", column: "user_id", value: "usr_1" });
    expect(client.calls).toContainEqual({ table: "reality_logs", op: "eq", column: "user_id", value: "usr_1" });
  });

  it("deletes the user row so cascades remove owned data", async () => {
    const client = fakeClient();
    await deleteUserData(client, "usr_1");

    expect(client.calls).toEqual([
      { table: "users", op: "from" },
      { table: "users", op: "delete" },
      { table: "users", op: "eq", column: "id", value: "usr_1" }
    ]);
  });

  it("maps confirmed reality logs to database column names", () => {
    const log: RealityLogInput = {
      plannedBlockId: "blk_1",
      actualSummary: "Edited for 43 minutes, watched tutorial for 12 minutes.",
      completionScore: 0.75,
      deviationReason: "Needed tutorial",
      actualCategories: [{ category: "work/video/editing", minutes: 43 }],
      confirmedByUser: true
    };

    expect(mapRealityLogInsert("usr_1", log)).toEqual({
      planned_block_id: "blk_1",
      user_id: "usr_1",
      actual_summary: "Edited for 43 minutes, watched tutorial for 12 minutes.",
      completion_score: 0.75,
      deviation_reason: "Needed tutorial",
      actual_categories_json: [{ category: "work/video/editing", minutes: 43 }],
      confirmed_by_user: true,
      source: "user_confirmed"
    });
  });

  it("maps frame batch metadata without raw frame storage by default", () => {
    expect(mapScreenFrameBatchInsert({
      userId: "usr_1",
      plannedBlockId: "blk_1",
      hash: "hash_1",
      capturedAt: "2026-06-06T13:00:00.000Z"
    })).toEqual({
      user_id: "usr_1",
      planned_block_id: "blk_1",
      screen_session_id: null,
      frame_hash: "hash_1",
      captured_at: "2026-06-06T13:00:00.000Z",
      raw_frame_stored_until: null
    });
  });
});
