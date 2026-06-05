import { describe, expect, it, vi } from "vitest";
import { POST as deleteData } from "@/app/api/privacy/delete/route";
import { GET as exportData } from "@/app/api/privacy/export/route";

vi.mock("@/lib/db/server", () => ({
  createServerSupabaseClient: vi.fn(async () => ({ db: true }))
}));

vi.mock("@/lib/db/bogi-store", () => ({
  exportUserData: vi.fn(async () => ({
    goals: [],
    plannedBlocks: [],
    screenSessions: [],
    screenFrameBatches: [],
    realityLogs: [],
    screenObservationSummaries: [],
    dailySummaries: [],
    weeklySummaries: [],
    monthlySummaries: [],
    userPatterns: [],
    calendarConnections: [],
    agentRuns: []
  })),
  deleteUserData: vi.fn(async () => undefined)
}));

describe("privacy export/delete", () => {
  it("exports user-owned data collections", async () => {
    const response = await exportData(new Request("http://127.0.0.1/api/privacy/export?userId=usr_1"));
    expect(await response.json()).toMatchObject({
      plannedBlocks: [],
      realityLogs: [],
      screenObservationSummaries: [],
      agentRuns: []
    });
  });

  it("deletes user data", async () => {
    const response = await deleteData(new Request("http://127.0.0.1/api/privacy/delete", {
      method: "POST",
      body: JSON.stringify({ userId: "usr_1" })
    }));
    expect(await response.json()).toEqual({ deleted: true });
  });
});
