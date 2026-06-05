import { describe, expect, it } from "vitest";
import { POST as deleteData } from "@/app/api/privacy/delete/route";
import { GET as exportData } from "@/app/api/privacy/export/route";

describe("privacy export/delete", () => {
  it("exports user-owned data collections", async () => {
    const response = await exportData();
    expect(await response.json()).toMatchObject({
      plannedBlocks: [],
      realityLogs: [],
      screenObservationSummaries: []
    });
  });

  it("deletes user data", async () => {
    const response = await deleteData();
    expect(await response.json()).toEqual({ deleted: true });
  });
});
