import { describe, expect, it } from "vitest";
import { mapPlannedBlockInsert, mapCalendarConnectionInsert } from "@/lib/db/bogi-store";

describe("bogi planning store mappings", () => {
  it("maps planned blocks to database column names", () => {
    expect(mapPlannedBlockInsert("usr_1", {
      title: "Edit video",
      start: "2026-06-06T13:00:00.000Z",
      end: "2026-06-06T14:00:00.000Z",
      successCriteria: "Rough cut first 3 minutes",
      category: "work/video"
    }, "evt_1")).toEqual({
      user_id: "usr_1",
      calendar_event_id: "evt_1",
      title: "Edit video",
      start_time: "2026-06-06T13:00:00.000Z",
      end_time: "2026-06-06T14:00:00.000Z",
      intention_text: "Edit video",
      success_criteria: "Rough cut first 3 minutes",
      category: "work/video",
      created_by: "planner_agent"
    });
  });

  it("maps google calendar connections without exposing provider variance", () => {
    expect(mapCalendarConnectionInsert("usr_1", {
      accessToken: "access",
      refreshToken: "refresh",
      syncToken: "sync",
      expiresAt: "2026-06-06T14:00:00.000Z"
    })).toEqual({
      user_id: "usr_1",
      provider: "google",
      access_token: "access",
      refresh_token: "refresh",
      sync_token: "sync",
      expires_at: "2026-06-06T14:00:00.000Z"
    });
  });
});
