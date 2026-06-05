import { describe, expect, it, vi } from "vitest";
import { POST } from "@/app/api/planner/route";

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

describe("planner route", () => {
  it("returns planner output", async () => {
    const response = await POST(new Request("http://127.0.0.1/api/planner", {
      method: "POST",
      body: JSON.stringify({ userRequest: "plan editing" })
    }));
    expect(await response.json()).toMatchObject({ blocks: [{ title: "Edit video" }] });
  });
});
