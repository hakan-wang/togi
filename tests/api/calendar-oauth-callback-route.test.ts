import { describe, expect, it, vi } from "vitest";
import { GET } from "@/app/api/calendar/oauth/callback/route";

const mocks = vi.hoisted(() => ({
  exchangeGoogleOAuthCode: vi.fn(async () => ({
    accessToken: "access",
    refreshToken: "refresh",
    expiresAt: "2026-06-06T14:00:00.000Z"
  })),
  saveCalendarConnection: vi.fn(async () => ({ id: "conn_1" }))
}));

vi.mock("@/lib/calendar/google-calendar", async () => {
  const actual = await vi.importActual<typeof import("@/lib/calendar/google-calendar")>("@/lib/calendar/google-calendar");
  return {
    ...actual,
    createGoogleOAuthClient: vi.fn(() => ({ oauth: true })),
    exchangeGoogleOAuthCode: mocks.exchangeGoogleOAuthCode
  };
});

vi.mock("@/lib/db/server", () => ({
  createServerSupabaseClient: vi.fn(async () => ({ db: true }))
}));

vi.mock("@/lib/db/bogi-store", async () => {
  const actual = await vi.importActual<typeof import("@/lib/db/bogi-store")>("@/lib/db/bogi-store");
  return { ...actual, saveCalendarConnection: mocks.saveCalendarConnection };
});

describe("calendar oauth callback route", () => {
  it("exchanges code and persists google calendar connection", async () => {
    const response = await GET(new Request("http://127.0.0.1/api/calendar/oauth/callback?code=code_1&state=usr_1"));

    expect(mocks.exchangeGoogleOAuthCode).toHaveBeenCalledWith({ oauth: true }, "code_1");
    expect(mocks.saveCalendarConnection).toHaveBeenCalledWith({ db: true }, "usr_1", {
      accessToken: "access",
      refreshToken: "refresh",
      expiresAt: "2026-06-06T14:00:00.000Z"
    });
    expect(response.status).toBe(307);
    expect(response.headers.get("location")).toBe("http://127.0.0.1/settings?calendar=connected");
  });

  it("rejects callbacks without user state", async () => {
    const response = await GET(new Request("http://127.0.0.1/api/calendar/oauth/callback?code=code_1"));
    expect(response.status).toBe(400);
  });
});
