import { describe, expect, it, vi } from "vitest";
import { POST } from "@/app/api/coach/route";

const mocks = vi.hoisted(() => ({
  runCoachAgent: vi.fn(async () => ({
    message: "Your 3-hour editing blocks are failing. Use 60-minute blocks.",
    proposedCalendarChanges: []
  })),
  saveAgentRun: vi.fn(async () => ({ id: "run_1" }))
}));

vi.mock("@/lib/agents/coach-agent", () => ({
  runCoachAgent: mocks.runCoachAgent
}));

vi.mock("@/lib/db/server", () => ({
  createServerSupabaseClient: vi.fn(async () => ({ db: true }))
}));

vi.mock("@/lib/db/bogi-store", async () => {
  const actual = await vi.importActual<typeof import("@/lib/db/bogi-store")>("@/lib/db/bogi-store");
  return { ...actual, saveAgentRun: mocks.saveAgentRun };
});

describe("coach route agent run logging", () => {
  it("records successful coach agent runs when user id is provided", async () => {
    const response = await POST(new Request("http://127.0.0.1/api/coach", {
      method: "POST",
      body: JSON.stringify({
        userId: "usr_1",
        message: "Why did I miss editing?",
        patterns: [{ pattern_key: "work/video" }],
        logs: [{ id: "log_1" }]
      })
    }));

    expect(mocks.saveAgentRun).toHaveBeenCalledWith({ db: true }, {
      userId: "usr_1",
      agentName: "coach_agent",
      input: {
        message: "Why did I miss editing?",
        patterns: [{ pattern_key: "work/video" }],
        logs: [{ id: "log_1" }]
      },
      output: {
        message: "Your 3-hour editing blocks are failing. Use 60-minute blocks.",
        proposedCalendarChanges: []
      },
      status: "succeeded"
    });
    expect(await response.json()).toMatchObject({
      message: "Your 3-hour editing blocks are failing. Use 60-minute blocks.",
      agentRun: { id: "run_1" }
    });
  });
});
