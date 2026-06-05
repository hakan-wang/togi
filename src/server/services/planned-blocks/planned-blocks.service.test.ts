import { describe, expect, it } from "vitest";
import { createMemoryStore } from "@/server/db/memory-store";
import { createPlannedBlockService } from "./planned-blocks.service";

describe("planned block service", () => {
  it("rejects vague plans because every planned block must be checkable", async () => {
    const service = createPlannedBlockService(createMemoryStore());

    await expect(
      service.create("user-1", {
        title: "Be productive",
        startTime: "2026-06-05T09:00:00.000Z",
        endTime: "2026-06-05T10:00:00.000Z",
        intentionText: "be productive",
        successCriteria: [],
        category: "work",
        createdBy: "user"
      })
    ).rejects.toThrow("checkable");
  });

  it("creates checkable planned blocks for owning user", async () => {
    const service = createPlannedBlockService(createMemoryStore());

    const block = await service.create("user-1", {
      title: "Draft launch notes",
      startTime: "2026-06-05T09:00:00.000Z",
      endTime: "2026-06-05T10:00:00.000Z",
      intentionText: "Draft launch notes for review",
      successCriteria: ["Write 5 bullet summary", "Send draft to Erik"],
      category: "work",
      createdBy: "planner_agent"
    });

    expect(block.userId).toBe("user-1");
    expect(block.status).toBe("planned");
    expect(block.successCriteria).toHaveLength(2);
  });
});
