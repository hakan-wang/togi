import { describe, expect, it } from "vitest";
import { shouldSampleFrame, targetCanvasSize } from "@/lib/screen/frame-sampler";

describe("frame sampler", () => {
  it("samples at the configured interval", () => {
    expect(shouldSampleFrame({ lastSampleAt: 0, now: 15000, intervalMs: 15000 })).toBe(true);
    expect(shouldSampleFrame({ lastSampleAt: 10000, now: 12000, intervalMs: 15000 })).toBe(false);
  });

  it("downscales wide frames to target width", () => {
    expect(targetCanvasSize({ width: 1920, height: 1080, targetWidth: 1024 })).toEqual({ width: 1024, height: 576 });
  });
});
