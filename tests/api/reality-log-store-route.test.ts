import { describe, expect, it, vi } from "vitest";
import { POST } from "@/app/api/reality-log/route";

const mocks = vi.hoisted(() => ({
  saveRealityLog: vi.fn(async () => ({ id: "log_1" }))
}));

vi.mock("@/lib/db/server", () => ({
  createServerSupabaseClient: vi.fn(async () => ({ db: true }))
}));

vi.mock("@/lib/db/bogi-store", async () => {
  const actual = await vi.importActual<typeof import("@/lib/db/bogi-store")>("@/lib/db/bogi-store");
  return { ...actual, saveRealityLog: mocks.saveRealityLog };
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

describe("reality log route store integration", () => {
  it("persists user-confirmed reality logs when user id is provided", async () => {
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

    expect(mocks.saveRealityLog).toHaveBeenCalledWith({ db: true }, "usr_1", expect.objectContaining({
      plannedBlockId: "blk_1",
      confirmedByUser: true
    }));
    expect(await response.json()).toMatchObject({
      plannedBlockId: "blk_1",
      savedRealityLog: { id: "log_1" }
    });
  });
});
