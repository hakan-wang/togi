import { describe, expect, it, vi } from "vitest";
import { POST } from "@/app/api/summaries/route";

const mocks = vi.hoisted(() => ({
  upsertStoredSummary: vi.fn(async () => ({ id: "sum_1" }))
}));

vi.mock("@/lib/db/server", () => ({
  createServerSupabaseClient: vi.fn(async () => ({ db: true }))
}));

vi.mock("@/lib/db/bogi-store", async () => {
  const actual = await vi.importActual<typeof import("@/lib/db/bogi-store")>("@/lib/db/bogi-store");
  return { ...actual, upsertStoredSummary: mocks.upsertStoredSummary };
});

describe("summaries POST route", () => {
  it("persists generated summaries by scope", async () => {
    const response = await POST(new Request("http://127.0.0.1/api/summaries", {
      method: "POST",
      body: JSON.stringify({
        userId: "usr_1",
        scope: "month",
        date: "2026-06-01",
        summary: "June had better lock-in completion.",
        stats: { plannedMinutes: 600, confirmedRealityMinutes: 480, gapMinutes: 120 }
      })
    }));

    expect(mocks.upsertStoredSummary).toHaveBeenCalledWith({ db: true }, {
      userId: "usr_1",
      scope: "month",
      date: "2026-06-01",
      summary: "June had better lock-in completion.",
      stats: { plannedMinutes: 600, confirmedRealityMinutes: 480, gapMinutes: 120 }
    });
    expect(await response.json()).toEqual({ summary: { id: "sum_1" } });
  });

  it("requires user id", async () => {
    const response = await POST(new Request("http://127.0.0.1/api/summaries", {
      method: "POST",
      body: JSON.stringify({ scope: "day" })
    }));
    expect(response.status).toBe(400);
  });
});
