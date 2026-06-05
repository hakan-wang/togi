import { describe, expect, it } from "vitest";
import { createMemoryStore } from "@/server/db/memory-store";
import { createAgentRunService } from "./agent-runs.service";
import { createPlannerAgentService } from "./planner-agent.service";
import { createRealityLogAgentService } from "./reality-log-agent.service";

describe("agent services", () => {
  it("planner turns vague intention into checkable block drafts and logs run", async () => {
    const store = createMemoryStore();
    const runs = createAgentRunService(store);
    const planner = createPlannerAgentService(runs);

    const output = await planner.plan("user-1", {
      request: "be productive tomorrow morning",
      calendarAvailability: [{ startTime: "2026-06-06T09:00:00.000Z", endTime: "2026-06-06T10:00:00.000Z" }],
      activeGoals: [{ id: "goal-1", title: "Ship launch", status: "active" }],
      userPatterns: []
    });

    expect(output.blocks[0]?.successCriteria.length).toBeGreaterThan(0);
    expect(output.blocks[0]?.intentionText).not.toBe("be productive");
    expect((await runs.list("user-1"))[0]?.agentName).toBe("planner");
  });

  it("reality log agent scores against success criteria and logs run", async () => {
    const store = createMemoryStore();
    const runs = createAgentRunService(store);
    const agent = createRealityLogAgentService(runs);

    const output = await agent.draft("user-1", {
      plannedBlock: {
        id: "block-1",
        title: "Draft launch notes",
        intentionText: "Draft launch notes for review",
        successCriteria: ["Write 5 bullet summary", "Send draft to Erik"]
      },
      userAnswer: "I wrote the bullets but did not send them.",
      historicalContext: []
    });

    expect(output.completionScore).toBeGreaterThan(0);
    expect(output.completionScore).toBeLessThan(1);
    expect(output.confirmedByUser).toBe(false);
    expect((await runs.list("user-1"))[0]?.agentName).toBe("reality_log");
  });
});
