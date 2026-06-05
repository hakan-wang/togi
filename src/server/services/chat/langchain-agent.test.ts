import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { ChatOpenAI } from "@langchain/openai";
import { createMemoryStore } from "@/server/db/memory-store";
import { createMemoryServices } from "@/server/services/container";
import { runTogiChat } from "./langchain-agent";

/**
 * Read OPENAI_API_KEY from .env.local WITHOUT mutating process.env, so these
 * live tests can inject it into an isolated model instance while the service
 * internals (reality-log drafting) keep their deterministic offline path.
 */
const readApiKey = (): string | undefined => {
  if (process.env.OPENAI_API_KEY) return process.env.OPENAI_API_KEY;
  try {
    const contents = readFileSync(resolve(process.cwd(), ".env.local"), "utf8");
    for (const line of contents.split("\n")) {
      const match = line.match(/^OPENAI_API_KEY=(.*)$/);
      if (match) return match[1].trim();
    }
  } catch {
    // no .env.local — live tests skip
  }
  return undefined;
};

const apiKey = readApiKey();
const liveModel = () => new ChatOpenAI({ apiKey, model: "gpt-4.1-mini", temperature: 0 });

// These tests prove createAgent() actually decides to call tools via live
// inference. They skip when no OpenAI key is available (e.g. offline CI).
const liveDescribe = apiKey ? describe : describe.skip;

const seededBlock = {
  title: "Draft launch notes",
  startTime: "2026-06-06T09:00:00.000Z",
  endTime: "2026-06-06T10:00:00.000Z",
  intentionText: "Draft launch notes for review",
  successCriteria: ["Write a 5 bullet summary", "Send the draft to Erik"],
  category: "work",
  createdBy: "user" as const
};

liveDescribe("togi langchain agent (live)", () => {
  it("planning request makes the agent call create_planned_block", async () => {
    const services = createMemoryServices(createMemoryStore());

    const result = await runTogiChat({
      userId: "user-1",
      message:
        "Plan a 90 minute focused block tomorrow morning to write the first draft of my conference talk. Make it checkable.",
      services,
      model: liveModel()
    });

    expect(result.toolCalls.map((call) => call.name)).toContain("create_planned_block");
    expect(result.artifacts.plannedBlocks.length).toBeGreaterThan(0);
    expect(result.state.plannedBlocks.length).toBeGreaterThan(0);
    expect(result.assistantMessage.length).toBeGreaterThan(0);
  }, 60000);

  it("check-in request drafts a reality log without persisting it", async () => {
    const store = createMemoryStore();
    const services = createMemoryServices(store);
    const block = await services.plannedBlocks.create("user-1", seededBlock);

    const result = await runTogiChat({
      userId: "user-1",
      message: `Check-in for my "${block.title}" block: I wrote the 5 bullet summary but I never sent the draft to Erik.`,
      services,
      model: liveModel()
    });

    expect(result.toolCalls.map((call) => call.name)).toContain("draft_reality_log");
    expect(result.artifacts.realityDraft).not.toBeNull();
    // A draft is not truth: no reality log is persisted until the user confirms.
    expect(await services.realityLogs.list("user-1")).toHaveLength(0);
  }, 60000);

  it("coaching request reads state through tools", async () => {
    const store = createMemoryStore();
    const services = createMemoryServices(store);
    await services.goals.create("user-1", { title: "Ship the launch" });
    const block = await services.plannedBlocks.create("user-1", seededBlock);
    await services.realityLogs.create("user-1", {
      plannedBlockId: block.id,
      actualSummary: "Wrote the summary, did not send it.",
      completionScore: 0.5,
      deviationReason: "Ran out of time",
      actualCategories: ["writing"],
      confirmedByUser: true,
      source: "user"
    });

    const result = await runTogiChat({
      userId: "user-1",
      message: "How am I doing against my goals so far? Be honest.",
      services,
      model: liveModel()
    });

    const readTools = ["coach_from_history", "list_goals", "list_reality_logs", "list_planned_blocks"];
    expect(result.toolCalls.some((call) => readTools.includes(call.name))).toBe(true);
    expect(result.assistantMessage.length).toBeGreaterThan(0);
  }, 60000);
});
