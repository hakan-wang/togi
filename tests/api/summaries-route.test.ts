import { describe, expect, it, vi } from "vitest";
import { GET } from "@/app/api/summaries/route";

vi.mock("@/lib/db/server", () => ({
  createServerSupabaseClient: vi.fn(async () => ({ db: true }))
}));

vi.mock("@/lib/db/bogi-store", () => ({
  getStoredSummary: vi.fn(async () => ({
    scope: "week",
    summary: "Stored weekly summary.",
    stats: { plannedMinutes: 360, confirmedRealityMinutes: 282, gapMinutes: 78 }
  }))
}));

describe("summaries route", () => {
  it("returns requested summary scope", async () => {
    const response = await GET(new Request("http://127.0.0.1/api/summaries?userId=usr_1&scope=week"));
    expect(await response.json()).toMatchObject({ scope: "week" });
  });
});
