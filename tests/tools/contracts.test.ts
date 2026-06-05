import { describe, expect, it } from "vitest";
import {
  plannerOutputSchema,
  realityLogInputSchema,
  screenObservationOutputSchema
} from "@/lib/zod/contracts";

describe("Bogi contracts", () => {
  it("requires concrete planner blocks", () => {
    const parsed = plannerOutputSchema.parse({
      blocks: [{
        title: "Edit video",
        start: "2026-06-06T13:00:00.000Z",
        end: "2026-06-06T14:00:00.000Z",
        successCriteria: "Rough cut first 3 minutes",
        category: "work/video"
      }]
    });
    expect(parsed.blocks[0]?.successCriteria).toContain("Rough cut");
  });

  it("rejects vague planner blocks", () => {
    expect(() => plannerOutputSchema.parse({
      blocks: [{
        title: "Be productive",
        start: "2026-06-06T13:00:00.000Z",
        end: "2026-06-06T14:00:00.000Z",
        successCriteria: "Be productive",
        category: "work"
      }]
    })).toThrow();
  });

  it("parses user-confirmed reality logs", () => {
    const parsed = realityLogInputSchema.parse({
      plannedBlockId: "blk_123",
      actualSummary: "Edited video for 43 minutes.",
      completionScore: 0.75,
      deviationReason: "Needed tutorial",
      actualCategories: [{ category: "work/video/editing", minutes: 43 }],
      confirmedByUser: true
    });
    expect(parsed.confirmedByUser).toBe(true);
  });

  it("parses screen observation summaries", () => {
    const parsed = screenObservationOutputSchema.parse({
      blockId: "blk_123",
      window: "13:00-13:15",
      observedActivities: [{ activity: "video editing", estimatedMinutes: 9, confidence: 0.82 }],
      summary: "Mostly editing."
    });
    expect(parsed.observedActivities[0]?.confidence).toBeGreaterThan(0.8);
  });
});
