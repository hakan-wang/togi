import { describe, expect, it } from "vitest";
import { mapAgentRunInsert, saveAgentRun } from "@/lib/db/bogi-store";

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
                  return { data: { id: "run_1" }, error: null };
                }
              };
            }
          };
        }
      };
    }
  };
}

describe("agent run store helpers", () => {
  it("maps agent runs to database column names", () => {
    expect(mapAgentRunInsert({
      userId: "usr_1",
      agentName: "coach_agent",
      input: { message: "Why did I miss editing?" },
      output: { message: "Use 60-minute blocks." },
      status: "succeeded"
    })).toEqual({
      user_id: "usr_1",
      agent_name: "coach_agent",
      input_json: { message: "Why did I miss editing?" },
      output_json: { message: "Use 60-minute blocks." },
      status: "succeeded"
    });
  });

  it("saves agent run audit records", async () => {
    const client = fakeInsertClient();
    const saved = await saveAgentRun(client, {
      userId: "usr_1",
      agentName: "coach_agent",
      input: { message: "Why did I miss editing?" },
      output: { message: "Use 60-minute blocks." },
      status: "succeeded"
    });

    expect(saved).toEqual({ id: "run_1" });
    expect(client.calls).toContainEqual({
      table: "agent_runs",
      op: "insert",
      value: {
        user_id: "usr_1",
        agent_name: "coach_agent",
        input_json: { message: "Why did I miss editing?" },
        output_json: { message: "Use 60-minute blocks." },
        status: "succeeded"
      }
    });
  });
});
