import { describe, expect, it } from "vitest";
import { buildRealityLogPrompt, parseRealityLog } from "@/lib/agents/reality-log-agent";

describe("reality log agent", () => {
  it("states that screen evidence is not final truth", () => {
    expect(buildRealityLogPrompt()).toContain("Screen evidence is not final truth");
  });

  it("parses confirmed reality", () => {
    const parsed = parseRealityLog({
      plannedBlockId: "blk_123",
      actualSummary: "Edited for 43 minutes, watched tutorial for 12 minutes.",
      completionScore: 0.75,
      deviationReason: "Needed tutorial",
      actualCategories: [{ category: "work/video/editing", minutes: 43 }],
      confirmedByUser: true
    });
    expect(parsed.confirmedByUser).toBe(true);
  });
});
