import { describe, expect, it } from "vitest";
import { blockEndedEvent } from "@/lib/workflows/block-ended";
import { frameBatchReadyEvent } from "@/lib/workflows/frame-batch-ready";

describe("workflow events", () => {
  it("names block-ended workflow event", () => {
    expect(blockEndedEvent).toBe("calendar.block.ended");
  });

  it("names frame-batch workflow event", () => {
    expect(frameBatchReadyEvent).toBe("lockin.frame_batch.ready");
  });
});
