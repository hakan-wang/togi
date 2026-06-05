import { describe, expect, it } from "vitest";
import { createMemoryStore } from "@/server/db/memory-store";
import { createPlannedBlockService } from "@/server/services/planned-blocks/planned-blocks.service";
import { createRealityLogService } from "./reality-logs.service";

describe("reality log service", () => {
  it("stores user-confirmed reality against owned planned block", async () => {
    const store = createMemoryStore();
    const plannedBlocks = createPlannedBlockService(store);
    const realityLogs = createRealityLogService(store);
    const block = await plannedBlocks.create("user-1", {
      title: "Draft launch notes",
      startTime: "2026-06-05T09:00:00.000Z",
      endTime: "2026-06-05T10:00:00.000Z",
      intentionText: "Draft launch notes for review",
      successCriteria: ["Write 5 bullet summary"],
      category: "work",
      createdBy: "user"
    });

    const log = await realityLogs.create("user-1", {
      plannedBlockId: block.id,
      actualSummary: "Wrote 3 bullets and identified missing metrics.",
      completionScore: 0.6,
      deviationReason: "Metrics source was not ready.",
      actualCategories: ["writing", "planning"],
      confirmedByUser: true,
      source: "user"
    });

    expect(log.plannedBlockId).toBe(block.id);
    expect(log.confirmedByUser).toBe(true);
  });

  it("prevents cross-user reality logs", async () => {
    const store = createMemoryStore();
    const plannedBlocks = createPlannedBlockService(store);
    const realityLogs = createRealityLogService(store);
    const block = await plannedBlocks.create("user-1", {
      title: "Draft launch notes",
      startTime: "2026-06-05T09:00:00.000Z",
      endTime: "2026-06-05T10:00:00.000Z",
      intentionText: "Draft launch notes for review",
      successCriteria: ["Write 5 bullet summary"],
      category: "work",
      createdBy: "user"
    });

    await expect(
      realityLogs.create("user-2", {
        plannedBlockId: block.id,
        actualSummary: "Did something else.",
        completionScore: 0.2,
        deviationReason: "Wrong block.",
        actualCategories: ["admin"],
        confirmedByUser: true,
        source: "user"
      })
    ).rejects.toThrow("not found");
  });

  it("rejects unconfirmed reality logs because persisted reality is user-confirmed truth", async () => {
    const store = createMemoryStore();
    const plannedBlocks = createPlannedBlockService(store);
    const realityLogs = createRealityLogService(store);
    const block = await plannedBlocks.create("user-1", {
      title: "Draft launch notes",
      startTime: "2026-06-05T09:00:00.000Z",
      endTime: "2026-06-05T10:00:00.000Z",
      intentionText: "Draft launch notes for review",
      successCriteria: ["Write 5 bullet summary"],
      category: "work",
      createdBy: "user"
    });
    const unconfirmedInput = {
      plannedBlockId: block.id,
      actualSummary: "AI guessed this happened.",
      completionScore: 0.5,
      deviationReason: "Unconfirmed.",
      actualCategories: ["writing"],
      confirmedByUser: false,
      source: "reality_log_agent"
    };

    await expect(realityLogs.create("user-1", unconfirmedInput as never)).rejects.toThrow("confirmed");
  });
});
