import { describe, expect, it } from "vitest";
import type { PlannedBlock, RealityLog, ScreenObservationSummary } from "@/lib/db/types";

describe("db types", () => {
  it("models intention, reality, and observation records", () => {
    const block: PlannedBlock = {
      id: "blk_1",
      userId: "usr_1",
      calendarEventId: "evt_1",
      title: "Edit video",
      startTime: "2026-06-06T13:00:00.000Z",
      endTime: "2026-06-06T14:00:00.000Z",
      intentionText: "Edit videos for 60 min",
      successCriteria: "Rough cut first 3 minutes",
      category: "work/video",
      createdBy: "planner_agent"
    };
    const log: RealityLog = {
      id: "log_1",
      plannedBlockId: block.id,
      userId: block.userId,
      actualSummary: "Edited for 43 min and watched tutorial for 12 min.",
      completionScore: 0.75,
      deviationReason: "Needed tutorial",
      actualCategories: [{ category: "work/video/editing", minutes: 43 }],
      confirmedByUser: true,
      source: "user_confirmed"
    };
    const observation: ScreenObservationSummary = {
      id: "obs_1",
      plannedBlockId: block.id,
      screenSessionId: "ses_1",
      timeWindowStart: block.startTime,
      timeWindowEnd: block.endTime,
      observedActivities: [{ activity: "video editing", estimatedMinutes: 43, confidence: 0.82 }],
      confidence: 0.82,
      rawFramesStoredUntil: null
    };
    expect(log.plannedBlockId).toBe(block.id);
    expect(observation.observedActivities[0]?.activity).toBe("video editing");
  });
});
