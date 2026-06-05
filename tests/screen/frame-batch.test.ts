import { describe, expect, it } from "vitest";
import { addFrameToBatch, createFrameBatchFormData, type FrameBatchState } from "@/lib/screen/frame-batch";

const baseState: FrameBatchState = {
  seenHashes: new Set<string>(),
  frames: []
};

describe("frame batch helpers", () => {
  it("adds unique frames until the batch threshold is ready", () => {
    const first = addFrameToBatch(baseState, {
      capturedAt: "2026-06-06T13:00:00.000Z",
      hash: "hash_1",
      imageBase64: "base64_1"
    }, 2);
    const second = addFrameToBatch(first.state, {
      capturedAt: "2026-06-06T13:00:15.000Z",
      hash: "hash_2",
      imageBase64: "base64_2"
    }, 2);

    expect(first.ready).toBe(false);
    expect(second.ready).toBe(true);
    expect(second.state.frames).toHaveLength(2);
  });

  it("dedupes frames by hash", () => {
    const first = addFrameToBatch(baseState, {
      capturedAt: "2026-06-06T13:00:00.000Z",
      hash: "hash_1",
      imageBase64: "base64_1"
    }, 2);
    const duplicate = addFrameToBatch(first.state, {
      capturedAt: "2026-06-06T13:00:15.000Z",
      hash: "hash_1",
      imageBase64: "base64_duplicate"
    }, 2);

    expect(duplicate.added).toBe(false);
    expect(duplicate.state.frames).toHaveLength(1);
  });

  it("creates batch-ready form data without raw frame blobs", () => {
    const form = createFrameBatchFormData({
      userId: "usr_1",
      plannedBlockId: "blk_1",
      screenSessionId: "ses_1",
      timeWindowStart: "2026-06-06T13:00:00.000Z",
      timeWindowEnd: "2026-06-06T13:00:15.000Z",
      frames: [
        { capturedAt: "2026-06-06T13:00:00.000Z", hash: "hash_1", imageBase64: "base64_1" },
        { capturedAt: "2026-06-06T13:00:15.000Z", hash: "hash_2", imageBase64: "base64_2" }
      ]
    });

    expect(form.get("batchReady")).toBe("true");
    expect(form.get("hash")).toBe("hash_2");
    expect(form.get("frame")).toBeNull();
    expect(JSON.parse(String(form.get("framesJson")))).toEqual([
      { capturedAt: "2026-06-06T13:00:00.000Z", imageBase64: "base64_1" },
      { capturedAt: "2026-06-06T13:00:15.000Z", imageBase64: "base64_2" }
    ]);
  });
});
