import { describe, expect, it } from "vitest";
import { mapPatternUpsert, getRelevantPatterns, upsertUserPattern } from "@/lib/db/bogi-store";

function fakePatternClient() {
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
                  return { data: { id: "pat_1" }, error: null };
                }
              };
            }
          };
        },
        select(columns: string) {
          calls.push({ table, op: "select", columns });
          return {
            eq(column: string, value: string) {
              calls.push({ table, op: "eq", column, value });
              return {
                ilike(columnName: string, pattern: string) {
                  calls.push({ table, op: "ilike", column: columnName, pattern });
                  return {
                    order(columnToOrder: string, options: Record<string, unknown>) {
                      calls.push({ table, op: "order", column: columnToOrder, options });
                      return { data: [{ pattern_key: "work/video", recommendation: "Use 60-minute blocks." }], error: null };
                    }
                  };
                }
              };
            }
          };
        }
      };
    }
  };
}

describe("pattern store helpers", () => {
  it("maps learned patterns to user_patterns upsert shape", () => {
    expect(mapPatternUpsert("usr_1", {
      patternKey: "work/video/editing_blocks_over_120_min_fail",
      evidence: { attempts: 9, successes: 2 },
      recommendation: "Plan editing in 60-minute blocks."
    })).toEqual({
      user_id: "usr_1",
      pattern_key: "work/video/editing_blocks_over_120_min_fail",
      evidence_json: { attempts: 9, successes: 2 },
      recommendation: "Plan editing in 60-minute blocks."
    });
  });

  it("upserts learned user patterns by user and key", async () => {
    const client = fakePatternClient();
    const saved = await upsertUserPattern(client, "usr_1", {
      patternKey: "work/video/editing_blocks_over_120_min_fail",
      evidence: { attempts: 9, successes: 2 },
      recommendation: "Plan editing in 60-minute blocks."
    });

    expect(saved).toEqual({ id: "pat_1" });
    expect(client.calls).toContainEqual({
      table: "user_patterns",
      op: "upsert",
      value: {
        user_id: "usr_1",
        pattern_key: "work/video/editing_blocks_over_120_min_fail",
        evidence_json: { attempts: 9, successes: 2 },
        recommendation: "Plan editing in 60-minute blocks."
      },
      options: { onConflict: "user_id,pattern_key" }
    });
  });

  it("reads category-relevant patterns for planner and coach context", async () => {
    const client = fakePatternClient();
    const patterns = await getRelevantPatterns(client, "usr_1", "work/video");

    expect(patterns).toEqual([{ pattern_key: "work/video", recommendation: "Use 60-minute blocks." }]);
    expect(client.calls).toContainEqual({ table: "user_patterns", op: "ilike", column: "pattern_key", pattern: "work/video%" });
  });
});
