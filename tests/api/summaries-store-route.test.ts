import { describe, expect, it, vi } from "vitest";
import { GET } from "@/app/api/summaries/route";

const mocks = vi.hoisted(() => ({
  getStoredSummary: vi.fn(async () => ({
    scope: "week",
    summary: "Four planned blocks became three confirmed work blocks.",
    stats: { plannedMinutes: 240, confirmedRealityMinutes: 180, gapMinutes: 60 }
  }))
}));

vi.mock("@/lib/db/server", () => ({
  createServerSupabaseClient: vi.fn(async () => ({ db: true }))
}));

vi.mock("@/lib/db/bogi-store", async () => {
  const actual = await vi.importActual<typeof import("@/lib/db/bogi-store")>("@/lib/db/bogi-store");
  return { ...actual, getStoredSummary: mocks.getStoredSummary };
});

describe("summaries route store integration", () => {
  it("returns stored summaries for user and scope", async () => {
    const response = await GET(new Request("http://127.0.0.1/api/summaries?userId=usr_1&scope=week&date=2026-06-01"));

    expect(mocks.getStoredSummary).toHaveBeenCalledWith({ db: true }, {
      userId: "usr_1",
      scope: "week",
      date: "2026-06-01"
    });
    expect(await response.json()).toEqual({
      scope: "week",
      summary: "Four planned blocks became three confirmed work blocks.",
      stats: { plannedMinutes: 240, confirmedRealityMinutes: 180, gapMinutes: 60 }
    });
  });

  it("requires user id for stored summaries", async () => {
    const response = await GET(new Request("http://127.0.0.1/api/summaries?scope=day"));
    expect(response.status).toBe(400);
  });
});
