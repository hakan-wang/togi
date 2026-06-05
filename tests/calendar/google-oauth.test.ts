import { describe, expect, it, vi } from "vitest";
import { buildGoogleCalendarAuthUrl, exchangeGoogleOAuthCode } from "@/lib/calendar/google-calendar";

describe("google calendar oauth helpers", () => {
  it("builds consent URL with calendar scope and encoded user state", () => {
    const client = {
      generateAuthUrl: vi.fn(() => "https://accounts.google.com/o/oauth2/v2/auth?state=usr_1")
    };

    expect(buildGoogleCalendarAuthUrl(client, "usr_1")).toBe("https://accounts.google.com/o/oauth2/v2/auth?state=usr_1");
    expect(client.generateAuthUrl).toHaveBeenCalledWith({
      access_type: "offline",
      prompt: "consent",
      scope: ["https://www.googleapis.com/auth/calendar.events"],
      state: "usr_1"
    });
  });

  it("exchanges oauth code for normalized tokens", async () => {
    const client = {
      getToken: vi.fn(async () => ({
        tokens: {
          access_token: "access",
          refresh_token: "refresh",
          expiry_date: Date.parse("2026-06-06T14:00:00.000Z")
        }
      }))
    };

    await expect(exchangeGoogleOAuthCode(client, "code_1")).resolves.toEqual({
      accessToken: "access",
      refreshToken: "refresh",
      expiresAt: "2026-06-06T14:00:00.000Z"
    });
  });
});
