import { describe, expect, it, vi } from "vitest";
import { POST } from "@/app/api/reality-log/route";

const mocks = vi.hoisted(() => ({
  saveRealityLog: vi.fn(async () => ({ id: "log_1" })),
  saveAgentRun: vi.fn(async () => ({ id: "run_reality" }))
}));

vi.mock("@/lib/db/server", () => ({
  createServerSupabaseClient: vi.fn(async () => ({ db: true }))
}));

vi.mock("@/lib/db/bogi-store", async () => {
  const actual = await vi.importActual<typeof import("@/lib/db/bogi-store")>("@/lib/db/bogi-store");
  return {
    ...actual,
    saveRealityLog: mocks.saveRealityLog,
    saveAgentRun: mocks.saveAgentRun
  };
});

vi.mock("@/lib/agents/reality-log-agent", () => ({
  runRealityLogAgent: vi.fn(async () => ({
    plannedBlockId: "blk_1",
    actualSummary: "Edited for 43 minutes, watched tutorial for 12 minutes.",
    completionScore: 0.75,
    deviationReason: "Needed tutorial",
    actualCategories: [{ category: "work/video/editing", minutes: 43 }],
    confirmedByUser: true
  }))
}));

describe("reality log route agent run logging", () => {
  it("records successful reality log agent runs when user id is provided", async () => {
    const response = await POST(new Request("http://127.0.0.1/api/reality-log", {
      method: "POST",
      body: JSON.stringify({
        userId: "usr_1",
        plannedBlockId: "blk_1",
        plannedTitle: "Edit video",
        observationSummary: "Mostly editing.",
        userCorrection: "Tutorial was needed."
      })
    }));

    expect(mocks.saveAgentRun).toHaveBeenCalledWith({ db: true }, {
      userId: "usr_1",
      agentName: "reality_log_agent",
      input: {
        plannedBlockId: "blk_1",
        plannedTitle: "Edit video",
        observationSummary: "Mostly editing.",
        userCorrection: "Tutorial was needed."
      },
      output: expect.objectContaining({ confirmedByUser: true }),
      status: "succeeded"
    });
    expect(await response.json()).toMatchObject({ agentRun: { id: "run_reality" } });
  });
});
