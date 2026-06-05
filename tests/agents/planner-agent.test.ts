import { describe, expect, it } from "vitest";
import { buildPlannerPrompt, parsePlannerOutput } from "@/lib/agents/planner-agent";

describe("planner agent", () => {
  it("includes concrete planning rules", () => {
    expect(buildPlannerPrompt()).toContain("No vague blocks");
    expect(buildPlannerPrompt()).toContain("Every block must be checkable");
  });

  it("parses concrete blocks", () => {
    const parsed = parsePlannerOutput({
      blocks: [{
        title: "Edit video",
        start: "2026-06-06T13:00:00.000Z",
        end: "2026-06-06T14:00:00.000Z",
        successCriteria: "Rough cut first 3 minutes",
        category: "work/video"
      }]
    });
    expect(parsed.blocks[0]?.category).toBe("work/video");
  });
});
