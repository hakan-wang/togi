import { describe, expect, it, vi } from "vitest";
import { POST } from "@/app/api/reality-log/route";

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

describe("reality log route", () => {
  it("returns user-confirmed reality log output", async () => {
    const response = await POST(new Request("http://127.0.0.1/api/reality-log", {
      method: "POST",
      body: JSON.stringify({
        plannedBlockId: "blk_1",
        plannedTitle: "Edit video",
        observationSummary: "Mostly editing.",
        userCorrection: "Tutorial was necessary."
      })
    }));

    expect(await response.json()).toMatchObject({
      plannedBlockId: "blk_1",
      confirmedByUser: true
    });
  });
});
