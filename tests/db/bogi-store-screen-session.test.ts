import { describe, expect, it } from "vitest";
import { endScreenSession, mapScreenSessionInsert, startScreenSession } from "@/lib/db/bogi-store";

function fakeSessionClient() {
  const calls: unknown[] = [];
  return {
    calls,
    from(table: string) {
      calls.push({ table, op: "from" });
      return {
        insert(value: Record<string, unknown>) {
          calls.push({ table, op: "insert", value });
          return {
            select(columns: string) {
              calls.push({ table, op: "select", columns });
              return {
                async single() {
                  return { data: { id: "ses_1" }, error: null };
                }
              };
            }
          };
        },
        update(value: Record<string, unknown>) {
          calls.push({ table, op: "update", value });
          return {
            eq(column: string, value: string) {
              calls.push({ table, op: "eq", column, value });
              return {
                select(columns: string) {
                  calls.push({ table, op: "select", columns });
                  return {
                    async single() {
                      return { data: { id: "ses_1", ended_at: "2026-06-06T14:00:00.000Z" }, error: null };
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

describe("screen session store helpers", () => {
  it("maps screen session starts to database columns", () => {
    expect(mapScreenSessionInsert({
      userId: "usr_1",
      plannedBlockId: "blk_1",
      captureSurface: "browser",
      rawFramesEnabled: false
    })).toEqual({
      user_id: "usr_1",
      planned_block_id: "blk_1",
      capture_surface: "browser",
      raw_frames_enabled: false
    });
  });

  it("starts persisted screen sessions", async () => {
    const client = fakeSessionClient();
    const saved = await startScreenSession(client, {
      userId: "usr_1",
      plannedBlockId: "blk_1",
      captureSurface: "browser",
      rawFramesEnabled: false
    });

    expect(saved).toEqual({ id: "ses_1" });
    expect(client.calls).toContainEqual({
      table: "screen_sessions",
      op: "insert",
      value: {
        user_id: "usr_1",
        planned_block_id: "blk_1",
        capture_surface: "browser",
        raw_frames_enabled: false
      }
    });
  });

  it("ends persisted screen sessions", async () => {
    const client = fakeSessionClient();
    await expect(endScreenSession(client, "ses_1", "2026-06-06T14:00:00.000Z")).resolves.toEqual({
      id: "ses_1",
      ended_at: "2026-06-06T14:00:00.000Z"
    });
    expect(client.calls).toContainEqual({
      table: "screen_sessions",
      op: "update",
      value: { ended_at: "2026-06-06T14:00:00.000Z" }
    });
  });
});
