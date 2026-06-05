import { describe, expect, it } from "vitest";
import { buildGoogleCalendarAuthUrl } from "../src/services/googleCalendarOAuth";

describe("Google Calendar OAuth", () => {
  it("builds an authorization URL with minimal calendar scope", () => {
    const url = buildGoogleCalendarAuthUrl({
      clientId: "client_1",
      redirectUri: "https://api.bogi.app/google/callback",
      state: "state_1"
    });

    expect(url.hostname).toBe("accounts.google.com");
    expect(url.searchParams.get("scope")).toBe("https://www.googleapis.com/auth/calendar.events");
    expect(url.searchParams.get("access_type")).toBe("offline");
  });
});
