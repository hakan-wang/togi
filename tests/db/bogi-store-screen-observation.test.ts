import { describe, expect, it } from "vitest";
import { mapScreenObservationSummaryInsert } from "@/lib/db/bogi-store";

describe("screen observation summary store mapping", () => {
  it("maps observer output to database column names", () => {
    expect(mapScreenObservationSummaryInsert({
      plannedBlockId: "blk_1",
      screenSessionId: "ses_1",
      timeWindowStart: "2026-06-06T13:00:00.000Z",
      timeWindowEnd: "2026-06-06T13:15:00.000Z",
      observation: {
        blockId: "blk_1",
        window: "13:00-13:15",
        observedActivities: [{ activity: "video editing", estimatedMinutes: 12, confidence: 0.82 }],
        summary: "Mostly editing."
      }
    })).toEqual({
      planned_block_id: "blk_1",
      screen_session_id: "ses_1",
      time_window_start: "2026-06-06T13:00:00.000Z",
      time_window_end: "2026-06-06T13:15:00.000Z",
      observed_activities_json: [{ activity: "video editing", estimatedMinutes: 12, confidence: 0.82 }],
      confidence: 0.82,
      raw_frames_stored_until: null
    });
  });
});
