import { describe, expect, it } from "vitest";
import { saveCalendarConnection } from "@/lib/db/bogi-store";

function fakeInsertClient() {
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
                  return { data: { id: "conn_1" }, error: null };
                }
              };
            }
          };
        }
      };
    }
  };
}

describe("calendar connection store", () => {
  it("saves google calendar OAuth tokens", async () => {
    const client = fakeInsertClient();
    const saved = await saveCalendarConnection(client, "usr_1", {
      accessToken: "access",
      refreshToken: "refresh",
      syncToken: "sync",
      expiresAt: "2026-06-06T14:00:00.000Z"
    });

    expect(saved).toEqual({ id: "conn_1" });
    expect(client.calls).toContainEqual({
      table: "calendar_connections",
      op: "insert",
      value: {
        user_id: "usr_1",
        provider: "google",
        access_token: "access",
        refresh_token: "refresh",
        sync_token: "sync",
        expires_at: "2026-06-06T14:00:00.000Z"
      }
    });
  });
});
