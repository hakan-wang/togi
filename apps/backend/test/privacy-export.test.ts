import { describe, expect, it } from "vitest";
import { buildPrivacyExport } from "../src/services/privacyExport";

describe("privacy export", () => {
  it("includes version and user id", () => {
    expect(buildPrivacyExport("user_1")).toEqual({
      version: 1,
      userId: "user_1",
      plannedBlocks: [],
      realityLogs: [],
      summaries: []
    });
  });
});
