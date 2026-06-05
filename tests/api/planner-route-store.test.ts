import { describe, expect, it, vi } from "vitest";
import { POST } from "@/app/api/planner/route";

const mocks = vi.hoisted(() => ({
  savePlannedBlocks: vi.fn(async () => [{ id: "blk_1", title: "Edit video" }])
}));

vi.mock("@/lib/db/server", () => ({
  createServerSupabaseClient: vi.fn(async () => ({ db: true }))
}));

vi.mock("@/lib/db/bogi-store", async () => {
  const actual = await vi.importActual<typeof import("@/lib/db/bogi-store")>("@/lib/db/bogi-store");
  return { ...actual, savePlannedBlocks: mocks.savePlannedBlocks };
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

describe("planner route store integration", () => {
  it("persists planned blocks when user id is provided", async () => {
    const response = await POST(new Request("http://127.0.0.1/api/planner", {
      method: "POST",
      body: JSON.stringify({ userId: "usr_1", userRequest: "plan editing" })
    }));

    expect(mocks.savePlannedBlocks).toHaveBeenCalledWith({ db: true }, "usr_1", [{
      title: "Edit video",
      start: "2026-06-06T13:00:00.000Z",
      end: "2026-06-06T14:00:00.000Z",
      successCriteria: "Rough cut first 3 minutes",
      category: "work/video"
    }]);
    expect(await response.json()).toMatchObject({
      blocks: [{ title: "Edit video" }],
      savedBlocks: [{ id: "blk_1" }]
    });
  });
});
