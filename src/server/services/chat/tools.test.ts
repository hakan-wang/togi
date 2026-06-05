import { beforeEach, describe, expect, it } from "vitest";
import { createMemoryStore } from "@/server/db/memory-store";
import { createMemoryServices } from "@/server/services/container";
import { createChatArtifactCollector } from "./schemas";
import { createTogiChatTools } from "./tools";

const USER = "user-1";

// Force the deterministic offline path of the underlying agent services so these
// tool tests never depend on live OpenAI.
beforeEach(() => {
  delete process.env.OPENAI_API_KEY;
});

const setup = () => {
  const store = createMemoryStore();
  const services = createMemoryServices(store);
  const collector = createChatArtifactCollector();
  const tools = createTogiChatTools({ userId: USER, services, collector });
  const byName = Object.fromEntries(tools.map((tool) => [tool.name, tool]));
  return { store, services, collector, byName };
};

const checkableBlock = {
  title: "Draft launch notes",
  startTime: "2026-06-06T09:00:00.000Z",
  endTime: "2026-06-06T10:00:00.000Z",
  intentionText: "Draft launch notes for review",
  successCriteria: ["Write 5 bullet summary", "Send draft to Erik"],
  category: "work"
};

describe("togi chat tools", () => {
  it("exposes all six required tools", () => {
    const { byName } = setup();
    expect(Object.keys(byName).sort()).toEqual(
      [
        "coach_from_history",
        "create_planned_block",
        "draft_reality_log",
        "list_goals",
        "list_planned_blocks",
        "list_reality_logs"
      ].sort()
    );
  });

  it("create_planned_block persists a checkable block and records the artifact", async () => {
    const { services, collector, byName } = setup();

    await byName.create_planned_block.invoke(checkableBlock);

    const blocks = await services.plannedBlocks.list(USER);
    expect(blocks).toHaveLength(1);
    expect(blocks[0]?.title).toBe("Draft launch notes");
    expect(blocks[0]?.successCriteria).toHaveLength(2);
    expect(collector.createdBlocks).toHaveLength(1);
    expect(collector.toolCalls).toContainEqual({ name: "create_planned_block", status: "completed" });
  });

  it("create_planned_block rejects a vague (non-checkable) block without persisting", async () => {
    const { services, collector, byName } = setup();

    // Schema-valid (non-empty criteria) but vague intention — the service's
    // checkable-block guard must reject it, recorded as a failed tool call.
    await byName.create_planned_block.invoke({
      title: "Be productive",
      startTime: "2026-06-06T09:00:00.000Z",
      endTime: "2026-06-06T10:00:00.000Z",
      intentionText: "be productive",
      successCriteria: ["do the thing"],
      category: "work"
    });

    expect(await services.plannedBlocks.list(USER)).toHaveLength(0);
    expect(collector.createdBlocks).toHaveLength(0);
    expect(collector.toolCalls).toContainEqual({ name: "create_planned_block", status: "failed" });
  });

  it("list_planned_blocks returns the created block", async () => {
    const { byName } = setup();
    await byName.create_planned_block.invoke(checkableBlock);

    const output = await byName.list_planned_blocks.invoke({});
    expect(output).toContain("Draft launch notes");
  });

  it("list_planned_blocks supports an optional status filter", async () => {
    const { byName } = setup();
    await byName.create_planned_block.invoke(checkableBlock);

    const planned = await byName.list_planned_blocks.invoke({ status: "planned" });
    expect(planned).toContain("Draft launch notes");

    const completed = await byName.list_planned_blocks.invoke({ status: "completed" });
    expect(completed).not.toContain("Draft launch notes");
  });

  it("list_goals returns the user's goals", async () => {
    const { services, byName } = setup();
    await services.goals.create(USER, { title: "Ship the launch" });

    const output = await byName.list_goals.invoke({});
    expect(output).toContain("Ship the launch");
  });

  it("draft_reality_log returns a draft and does NOT persist a reality log", async () => {
    const { services, collector, byName } = setup();
    const block = await services.plannedBlocks.create(USER, { ...checkableBlock, createdBy: "user" });

    const output = await byName.draft_reality_log.invoke({
      plannedBlockId: block.id,
      userAnswer: "I wrote the bullet summary but did not send the draft."
    });

    expect(collector.realityDraft).not.toBeNull();
    expect(collector.realityDraft?.confirmedByUser).toBe(false);
    expect(collector.realityDraft?.plannedBlockId).toBe(block.id);
    expect(output).toContain("draft");
    // Drafts are not truth: nothing persisted until the user confirms.
    expect(await services.realityLogs.list(USER)).toHaveLength(0);
    expect(collector.toolCalls).toContainEqual({ name: "draft_reality_log", status: "completed" });
  });

  it("list_reality_logs returns confirmed logs", async () => {
    const { services, byName } = setup();
    const block = await services.plannedBlocks.create(USER, { ...checkableBlock, createdBy: "user" });
    await services.realityLogs.create(USER, {
      plannedBlockId: block.id,
      actualSummary: "Finished the summary and sent it.",
      completionScore: 1,
      deviationReason: "",
      actualCategories: ["writing"],
      confirmedByUser: true,
      source: "user"
    });

    const output = await byName.list_reality_logs.invoke({});
    expect(output).toContain("Finished the summary");
  });

  it("coach_from_history returns grounded text", async () => {
    const { byName, collector } = setup();

    const output = await byName.coach_from_history.invoke({ question: "How am I doing this week?" });
    expect(typeof output).toBe("string");
    expect(output.length).toBeGreaterThan(0);
    expect(collector.toolCalls).toContainEqual({ name: "coach_from_history", status: "completed" });
  });
});
