import { describe, expect, it } from "vitest";
import { deriveEditingBlockPattern } from "@/lib/agents/pattern-learner-agent";

describe("pattern learner", () => {
  it("detects failed long editing blocks", () => {
    const result = deriveEditingBlockPattern({
      attempts: 9,
      successes: 2,
      avgActualMinutes: 54
    });
    expect(result.patternKey).toBe("editing_blocks_over_120_min_fail");
    expect(result.recommendation).toContain("60-minute blocks");
  });
});
