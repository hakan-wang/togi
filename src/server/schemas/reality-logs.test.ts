import { describe, expect, it } from "vitest";
import { createRealityLogSchema, realityLogSchema } from "./reality-logs";

describe("reality log schemas", () => {
  it("requires confirmed user truth for persisted reality log creation", () => {
    expect(() =>
      createRealityLogSchema.parse({
        plannedBlockId: "00000000-0000-4000-8000-000000000001",
        actualSummary: "AI inferred activity.",
        completionScore: 0.5,
        confirmedByUser: false
      })
    ).toThrow();
  });

  it("allows stored reality log records to represent confirmation state", () => {
    expect(
      realityLogSchema.parse({
        id: "00000000-0000-4000-8000-000000000002",
        userId: "user-1",
        plannedBlockId: "00000000-0000-4000-8000-000000000001",
        actualSummary: "User confirmed work.",
        completionScore: 1,
        deviationReason: "",
        actualCategories: [],
        confirmedByUser: true,
        source: "user",
        createdAt: "2026-06-05T09:00:00.000Z",
        updatedAt: "2026-06-05T09:00:00.000Z"
      })
    ).toMatchObject({ confirmedByUser: true });
  });
});
