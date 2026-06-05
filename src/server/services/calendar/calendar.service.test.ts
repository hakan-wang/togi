import { describe, expect, it } from "vitest";
import { createGoogleCalendarService, mapGoogleCalendarEvent } from "./calendar.service";

describe("google calendar service boundary", () => {
  it("builds Google OAuth URL when calendar credentials are configured", () => {
    const service = createGoogleCalendarService({
      clientId: "client-id",
      clientSecret: "client-secret",
      redirectUri: "https://togi.test/api/calendar/google/callback"
    });

    const url = service.createAuthorizationUrl("user-1");

    expect(url).toContain("accounts.google.com");
    expect(url).toContain("state=user-1");
    expect(url).toContain("calendar.events");
  });

  it("reports unconfigured OAuth when credentials are missing", () => {
    const service = createGoogleCalendarService({});

    expect(service.createAuthorizationUrl("user-1")).toBeNull();
  });

  it("maps Google events into Togi calendar events", () => {
    const event = mapGoogleCalendarEvent({
      id: "event-1",
      summary: "Draft plan",
      description: "Write checkable criteria",
      start: { dateTime: "2026-06-05T09:00:00.000Z" },
      end: { dateTime: "2026-06-05T10:00:00.000Z" }
    });

    expect(event).toEqual({
      id: "event-1",
      title: "Draft plan",
      description: "Write checkable criteria",
      startTime: "2026-06-05T09:00:00.000Z",
      endTime: "2026-06-05T10:00:00.000Z"
    });
  });
});
