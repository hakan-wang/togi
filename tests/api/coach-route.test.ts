import { describe, expect, it, vi } from "vitest";
import { POST } from "@/app/api/coach/route";

vi.mock("@/lib/agents/coach-agent", () => ({
  runCoachAgent: vi.fn(async () => ({
    message: "Your 3-hour editing blocks are failing. Use 60-minute blocks.",
    proposedCalendarChanges: []
  }))
}));

describe("coach route", () => {
  it("returns blunt coach feedback", async () => {
    const response = await POST(new Request("http://127.0.0.1/api/coach", {
      method: "POST",
      body: JSON.stringify({
        message: "Why did I miss editing?",
        patterns: [],
        logs: []
      })
    }));

    expect(await response.json()).toEqual({
      message: "Your 3-hour editing blocks are failing. Use 60-minute blocks.",
      proposedCalendarChanges: [],
      agentRun: null
    });
  });
});
