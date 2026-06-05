import { describe, expect, it, vi } from "vitest";
import { handleBlockEnded } from "@/lib/workflows/block-ended";
import { handleDailySummary } from "@/lib/workflows/daily-summary";
import { handleFrameBatchReady } from "@/lib/workflows/frame-batch-ready";
import { handleWeeklySummary } from "@/lib/workflows/weekly-summary";

describe("workflow handlers", () => {
  it("block ended workflow requests a reality confirmation", async () => {
    const enqueueRealityConfirmation = vi.fn(async () => ({ id: "job_1" }));

    await expect(handleBlockEnded({
      userId: "usr_1",
      plannedBlockId: "blk_1",
      endedAt: "2026-06-06T14:00:00.000Z"
    }, { enqueueRealityConfirmation })).resolves.toEqual({
      event: "calendar.block.ended",
      next: "reality_confirmation",
      job: { id: "job_1" }
    });

    expect(enqueueRealityConfirmation).toHaveBeenCalledWith({
      userId: "usr_1",
      plannedBlockId: "blk_1",
      endedAt: "2026-06-06T14:00:00.000Z"
    });
  });

  it("frame batch workflow runs observation", async () => {
    const observeFrameBatch = vi.fn(async () => ({ id: "obs_1" }));

    await expect(handleFrameBatchReady({
      userId: "usr_1",
      plannedBlockId: "blk_1",
      screenSessionId: "ses_1",
      frameCount: 3
    }, { observeFrameBatch })).resolves.toEqual({
      event: "lockin.frame_batch.ready",
      next: "screen_observation",
      observation: { id: "obs_1" }
    });

    expect(observeFrameBatch).toHaveBeenCalledWith({
      userId: "usr_1",
      plannedBlockId: "blk_1",
      screenSessionId: "ses_1",
      frameCount: 3
    });
  });

  it("daily summary workflow writes the day summary", async () => {
    const writeSummary = vi.fn(async () => ({ id: "sum_1" }));

    await expect(handleDailySummary({
      userId: "usr_1",
      day: "2026-06-06"
    }, { writeSummary })).resolves.toEqual({
      event: "day.ended",
      scope: "day",
      summary: { id: "sum_1" }
    });

    expect(writeSummary).toHaveBeenCalledWith({ userId: "usr_1", scope: "day", date: "2026-06-06" });
  });

  it("weekly summary workflow writes the week summary", async () => {
    const writeSummary = vi.fn(async () => ({ id: "sum_2" }));

    await expect(handleWeeklySummary({
      userId: "usr_1",
      weekStart: "2026-06-01"
    }, { writeSummary })).resolves.toEqual({
      event: "week.ended",
      scope: "week",
      summary: { id: "sum_2" }
    });

    expect(writeSummary).toHaveBeenCalledWith({ userId: "usr_1", scope: "week", date: "2026-06-01" });
  });
});
