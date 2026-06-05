import { describe, expect, it, vi } from "vitest";
import { POST as deleteData } from "@/app/api/privacy/delete/route";
import { GET as exportData } from "@/app/api/privacy/export/route";

vi.mock("@/lib/db/server", () => ({
  createServerSupabaseClient: vi.fn(async () => ({ db: true }))
}));

vi.mock("@/lib/db/bogi-store", () => ({
  exportUserData: vi.fn(async () => ({
    plannedBlocks: [{ id: "blk_1" }],
    realityLogs: [],
    screenObservationSummaries: [],
    dailySummaries: [],
    weeklySummaries: [],
    monthlySummaries: [],
    userPatterns: []
  })),
  deleteUserData: vi.fn(async () => undefined)
}));

describe("privacy routes store integration", () => {
  it("exports data for the requested user id", async () => {
    const response = await exportData(new Request("http://127.0.0.1/api/privacy/export?userId=usr_1"));
    expect(await response.json()).toMatchObject({ plannedBlocks: [{ id: "blk_1" }] });
  });

  it("requires user id for export", async () => {
    const response = await exportData(new Request("http://127.0.0.1/api/privacy/export"));
    expect(response.status).toBe(400);
  });

  it("deletes data for the requested user id", async () => {
    const response = await deleteData(new Request("http://127.0.0.1/api/privacy/delete", {
      method: "POST",
      body: JSON.stringify({ userId: "usr_1" })
    }));
    expect(await response.json()).toEqual({ deleted: true });
  });
});
