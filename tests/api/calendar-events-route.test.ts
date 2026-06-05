import { describe, expect, it } from "vitest";
import { POST } from "@/app/api/calendar/events/route";

describe("calendar events route", () => {
  it("maps planned blocks to google calendar event payloads", async () => {
    const response = await POST(new Request("http://127.0.0.1/api/calendar/events", {
      method: "POST",
      body: JSON.stringify({
        title: "Edit video",
        start: "2026-06-06T13:00:00.000Z",
        end: "2026-06-06T14:00:00.000Z",
        successCriteria: "Rough cut first 3 minutes",
        category: "work/video"
      })
    }));

    expect(await response.json()).toEqual({
      event: {
        summary: "Edit video",
        description: "Success criteria: Rough cut first 3 minutes\nCategory: work/video",
        start: { dateTime: "2026-06-06T13:00:00.000Z" },
        end: { dateTime: "2026-06-06T14:00:00.000Z" }
      }
    });
  });
});
