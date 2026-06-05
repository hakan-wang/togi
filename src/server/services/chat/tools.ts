import { tool } from "@langchain/core/tools";
import { z } from "zod";
import type { Goal } from "@/server/schemas/goals";
import type { CreatePlannedBlockInput, PlannedBlock } from "@/server/schemas/planned-blocks";
import type { RealityLog } from "@/server/schemas/reality-logs";
import type { RealityLogAgentInput, RealityLogAgentOutput } from "@/server/schemas/agents";
import type { ChatArtifactCollector, ToolCall } from "./schemas";

/**
 * The slice of the Togi service container the chat tools depend on. Both the
 * in-memory and Supabase service implementations satisfy this structurally.
 */
export type TogiChatServices = {
  goals: { list(userId: string): Promise<Goal[]> };
  plannedBlocks: {
    list(userId: string): Promise<PlannedBlock[]>;
    get(userId: string, id: string): Promise<PlannedBlock>;
    create(userId: string, input: CreatePlannedBlockInput): Promise<PlannedBlock>;
  };
  realityLogs: { list(userId: string): Promise<RealityLog[]> };
  realityLogAgent: { draft(userId: string, input: RealityLogAgentInput): Promise<RealityLogAgentOutput> };
  coachAgent: { coach(userId: string, question: string): Promise<{ answer: string; evidence: unknown }> };
};

export type TogiToolContext = {
  userId: string;
  services: TogiChatServices;
  collector: ChatArtifactCollector;
};

const plannedBlockView = (block: PlannedBlock) => ({
  id: block.id,
  title: block.title,
  startTime: block.startTime,
  endTime: block.endTime,
  intentionText: block.intentionText,
  successCriteria: block.successCriteria,
  category: block.category,
  status: block.status
});

const errorMessage = (error: unknown) => (error instanceof Error ? error.message : "Unknown error");

/**
 * Build the LangChain tools for one chat request, bound to the authenticated
 * user, the service container, and a per-request artifact collector. Every tool
 * records its outcome in `collector.toolCalls`; on failure it returns a readable
 * error string so the agent can recover instead of crashing the loop.
 */
export const createTogiChatTools = (ctx: TogiToolContext) => {
  const { userId, services, collector } = ctx;

  const recorded = <Schema extends z.ZodTypeAny>(config: {
    name: string;
    description: string;
    schema: Schema;
    run: (input: z.infer<Schema>) => Promise<string>;
  }) =>
    tool(
      async (input: z.infer<Schema>) => {
        try {
          const result = await config.run(input);
          collector.toolCalls.push({ name: config.name, status: "completed" } satisfies ToolCall);
          return result;
        } catch (error) {
          collector.toolCalls.push({ name: config.name, status: "failed" } satisfies ToolCall);
          return `${config.name} failed: ${errorMessage(error)}`;
        }
      },
      { name: config.name, description: config.description, schema: config.schema }
    );

  const listGoals = recorded({
    name: "list_goals",
    description: "List the user's active and recent goals. Call this to ground plans and coaching in what the user is actually trying to achieve. Takes no arguments.",
    schema: z.object({}),
    run: async () => {
      const goals = await services.goals.list(userId);
      return JSON.stringify(goals.map((goal) => ({ id: goal.id, title: goal.title, status: goal.status, description: goal.description })));
    }
  });

  const listPlannedBlocks = recorded({
    name: "list_planned_blocks",
    description: "List the user's planned time blocks, optionally filtered by status (planned, completed, or cancelled). Call this to see what is already scheduled before planning. Omit the status filter when looking up a block to check in on — those are usually still 'planned'.",
    schema: z.object({
      status: z.enum(["planned", "completed", "cancelled"]).optional().describe("Optional status filter; omit to return all blocks")
    }),
    run: async ({ status }) => {
      const blocks = await services.plannedBlocks.list(userId);
      const filtered = status ? blocks.filter((block) => block.status === status) : blocks;
      return JSON.stringify(filtered.map(plannedBlockView));
    }
  });

  const createPlannedBlock = recorded({
    name: "create_planned_block",
    description:
      "Create one checkable planned time block for the user. Use this whenever the user wants to plan, schedule, or commit to focused work. Success criteria must be concrete and verifiable — vague intentions like 'be productive' are rejected.",
    schema: z.object({
      title: z.string().min(1).describe("Short title for the block"),
      startTime: z.string().describe("Start time as an ISO 8601 datetime, e.g. 2026-06-06T09:00:00.000Z"),
      endTime: z.string().describe("End time as an ISO 8601 datetime, after startTime"),
      intentionText: z.string().min(1).describe("Concrete intention for the block (not vague filler)"),
      successCriteria: z.array(z.string().min(1)).min(1).describe("One or more concrete, checkable success criteria"),
      category: z.string().min(1).describe("Category such as work, health, learning, or planning")
    }),
    run: async (input) => {
      const block = await services.plannedBlocks.create(userId, {
        title: input.title,
        startTime: input.startTime,
        endTime: input.endTime,
        intentionText: input.intentionText,
        successCriteria: input.successCriteria,
        category: input.category,
        createdBy: "planner_agent"
      });
      collector.createdBlocks.push(block);
      return `Created planned block "${block.title}". ${JSON.stringify(plannedBlockView(block))}`;
    }
  });

  const draftRealityLog = recorded({
    name: "draft_reality_log",
    description:
      "Draft a reality log for a planned block from the user's free-text answer about what actually happened. Call this immediately whenever the user describes how a planned block actually went (a check-in), after using list_planned_blocks to find the block id. This produces a DRAFT only — it is never persisted as truth. The user must explicitly confirm before it becomes a reality log.",
    schema: z.object({
      plannedBlockId: z.string().min(1).describe("The id of the planned block being reviewed"),
      userAnswer: z.string().min(1).describe("The user's free-text description of what actually happened")
    }),
    run: async ({ plannedBlockId, userAnswer }) => {
      const block = await services.plannedBlocks.get(userId, plannedBlockId);
      const draft = await services.realityLogAgent.draft(userId, {
        plannedBlock: {
          id: block.id,
          title: block.title,
          intentionText: block.intentionText,
          successCriteria: block.successCriteria
        },
        userAnswer,
        historicalContext: []
      });
      collector.realityDraft = { ...draft, plannedBlockId: block.id };
      return `Reality log draft (not yet confirmed): ${JSON.stringify(collector.realityDraft)}`;
    }
  });

  const listRealityLogs = recorded({
    name: "list_reality_logs",
    description: "List the user's recent confirmed reality logs — the ground truth of what actually happened. Call this to coach from real history. Takes no arguments.",
    schema: z.object({}),
    run: async () => {
      const logs = await services.realityLogs.list(userId);
      return JSON.stringify(
        logs.map((log) => ({
          id: log.id,
          plannedBlockId: log.plannedBlockId,
          actualSummary: log.actualSummary,
          completionScore: log.completionScore,
          deviationReason: log.deviationReason
        }))
      );
    }
  });

  const coachFromHistory = recorded({
    name: "coach_from_history",
    description:
      "Answer a coaching question grounded in the user's goals, plans, and confirmed reality logs. Use this for reflective 'how am I doing' style questions rather than scheduling.",
    schema: z.object({
      question: z.string().min(1).describe("The user's coaching question")
    }),
    run: async ({ question }) => {
      const result = await services.coachAgent.coach(userId, question);
      return result.answer;
    }
  });

  return [listGoals, listPlannedBlocks, createPlannedBlock, draftRealityLog, listRealityLogs, coachFromHistory];
};
