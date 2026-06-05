import { describe, expect, it } from "vitest";
import { toGoogleCalendarEvent } from "@/lib/calendar/google-calendar";

describe("toGoogleCalendarEvent", () => {
  it("maps a Bogi block to Google Calendar event shape", () => {
    expect(toGoogleCalendarEvent({
      title: "Edit video",
      start: "2026-06-06T13:00:00.000Z",
      end: "2026-06-06T14:00:00.000Z",
      successCriteria: "Rough cut first 3 minutes",
      category: "work/video"
    })).toEqual({
      summary: "Edit video",
      description: "Success criteria: Rough cut first 3 minutes\nCategory: work/video",
      start: { dateTime: "2026-06-06T13:00:00.000Z" },
      end: { dateTime: "2026-06-06T14:00:00.000Z" }
    });
  });
});
