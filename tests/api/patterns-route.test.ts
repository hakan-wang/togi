import { describe, expect, it, vi } from "vitest";
import { GET, POST } from "@/app/api/patterns/route";

const mocks = vi.hoisted(() => ({
  getRelevantPatterns: vi.fn(async () => [{ pattern_key: "work/video", recommendation: "Use 60-minute blocks." }]),
  upsertUserPattern: vi.fn(async () => ({ id: "pat_1" }))
}));

vi.mock("@/lib/db/server", () => ({
  createServerSupabaseClient: vi.fn(async () => ({ db: true }))
}));

vi.mock("@/lib/db/bogi-store", async () => {
  const actual = await vi.importActual<typeof import("@/lib/db/bogi-store")>("@/lib/db/bogi-store");
  return {
    ...actual,
    getRelevantPatterns: mocks.getRelevantPatterns,
    upsertUserPattern: mocks.upsertUserPattern
  };
});

describe("patterns route", () => {
  it("returns relevant patterns by user and category", async () => {
    const response = await GET(new Request("http://127.0.0.1/api/patterns?userId=usr_1&category=work/video"));

    expect(mocks.getRelevantPatterns).toHaveBeenCalledWith({ db: true }, "usr_1", "work/video");
    expect(await response.json()).toEqual({
      patterns: [{ pattern_key: "work/video", recommendation: "Use 60-minute blocks." }]
    });
  });

  it("requires user id to read patterns", async () => {
    const response = await GET(new Request("http://127.0.0.1/api/patterns?category=work/video"));
    expect(response.status).toBe(400);
  });

  it("upserts learned patterns", async () => {
    const response = await POST(new Request("http://127.0.0.1/api/patterns", {
      method: "POST",
      body: JSON.stringify({
        userId: "usr_1",
        patternKey: "work/video/editing_blocks_over_120_min_fail",
        evidence: { attempts: 9, successes: 2 },
        recommendation: "Plan editing in 60-minute blocks."
      })
    }));

    expect(mocks.upsertUserPattern).toHaveBeenCalledWith({ db: true }, "usr_1", {
      patternKey: "work/video/editing_blocks_over_120_min_fail",
      evidence: { attempts: 9, successes: 2 },
      recommendation: "Plan editing in 60-minute blocks."
    });
    expect(await response.json()).toEqual({ pattern: { id: "pat_1" } });
  });
});
