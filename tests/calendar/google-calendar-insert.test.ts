import { describe, expect, it, vi } from "vitest";
import { insertGoogleCalendarEvent } from "@/lib/calendar/google-calendar";

describe("insertGoogleCalendarEvent", () => {
  it("inserts Bogi blocks into the primary Google Calendar", async () => {
    const insert = vi.fn(async () => ({ data: { id: "gcal_evt_1" } }));
    const calendar = { events: { insert } };

    const eventId = await insertGoogleCalendarEvent(calendar, {
      title: "Edit video",
      start: "2026-06-06T13:00:00.000Z",
      end: "2026-06-06T14:00:00.000Z",
      successCriteria: "Rough cut first 3 minutes",
      category: "work/video"
    });

    expect(insert).toHaveBeenCalledWith({
      calendarId: "primary",
      requestBody: {
        summary: "Edit video",
        description: "Success criteria: Rough cut first 3 minutes\nCategory: work/video",
        start: { dateTime: "2026-06-06T13:00:00.000Z" },
        end: { dateTime: "2026-06-06T14:00:00.000Z" }
      }
    });
    expect(eventId).toBe("gcal_evt_1");
  });
});
