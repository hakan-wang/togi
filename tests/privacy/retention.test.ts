import { describe, expect, it } from "vitest";
import { getFrameRetentionPolicy } from "@/lib/privacy/retention";

describe("getFrameRetentionPolicy", () => {
  it("stores summaries only by default", () => {
    expect(getFrameRetentionPolicy({ rawFramesEnabled: false })).toEqual({
      storeRawFrames: false,
      deleteRawFramesAfterMinutes: 0,
      permanentStorage: "summaries_only"
    });
  });

  it("limits debug frames to 60 minutes", () => {
    expect(getFrameRetentionPolicy({ rawFramesEnabled: true })).toEqual({
      storeRawFrames: true,
      deleteRawFramesAfterMinutes: 60,
      permanentStorage: "summaries_only"
    });
  });
});
