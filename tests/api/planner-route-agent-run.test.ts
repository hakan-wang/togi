import { describe, expect, it, vi } from "vitest";
import { POST } from "@/app/api/planner/route";

const mocks = vi.hoisted(() => ({
  savePlannedBlocks: vi.fn(async () => [{ id: "blk_1" }]),
  saveAgentRun: vi.fn(async () => ({ id: "run_planner" }))
}));

vi.mock("@/lib/db/server", () => ({
  createServerSupabaseClient: vi.fn(async () => ({ db: true }))
}));

vi.mock("@/lib/db/bogi-store", async () => {
  const actual = await vi.importActual<typeof import("@/lib/db/bogi-store")>("@/lib/db/bogi-store");
  return {
    ...actual,
    savePlannedBlocks: mocks.savePlannedBlocks,
    saveAgentRun: mocks.saveAgentRun
  };
});

vi.mock("@/lib/agents/planner-agent", () => ({
  runPlannerAgent: vi.fn(async () => ({
    blocks: [{
      title: "Edit video",
      start: "2026-06-06T13:00:00.000Z",
      end: "2026-06-06T14:00:00.000Z",
      successCriteria: "Rough cut first 3 minutes",
      category: "work/video"
    }]
  }))
}));

describe("planner route agent run logging", () => {
  it("records successful planner agent runs when user id is provided", async () => {
    const response = await POST(new Request("http://127.0.0.1/api/planner", {
      method: "POST",
      body: JSON.stringify({ userId: "usr_1", userRequest: "plan editing", currentCalendar: [], relevantPatterns: [] })
    }));

    expect(mocks.saveAgentRun).toHaveBeenCalledWith({ db: true }, {
      userId: "usr_1",
      agentName: "planner_agent",
      input: { userRequest: "plan editing", currentCalendar: [], relevantPatterns: [] },
      output: { blocks: [expect.objectContaining({ title: "Edit video" })] },
      status: "succeeded"
    });
    expect(await response.json()).toMatchObject({ agentRun: { id: "run_planner" } });
  });
});
