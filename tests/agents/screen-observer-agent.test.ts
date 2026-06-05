import { describe, expect, it } from "vitest";
import { buildScreenObserverPrompt, parseScreenObservation } from "@/lib/agents/screen-observer-agent";

describe("screen observer agent", () => {
  it("is observer-only", () => {
    expect(buildScreenObserverPrompt()).toContain("Not a coach");
    expect(buildScreenObserverPrompt()).toContain("Just observer");
  });

  it("parses observations", () => {
    const parsed = parseScreenObservation({
      blockId: "blk_123",
      window: "13:00-13:15",
      observedActivities: [{ activity: "video editing", estimatedMinutes: 9, confidence: 0.82 }],
      summary: "Mostly editing."
    });
    expect(parsed.summary).toBe("Mostly editing.");
  });
});
