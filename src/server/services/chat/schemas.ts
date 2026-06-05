import { z } from "zod";
import { nonEmptyString, uuidSchema } from "@/server/schemas/common";
import { goalSchema } from "@/server/schemas/goals";
import { plannedBlockSchema } from "@/server/schemas/planned-blocks";
import { realityLogSchema } from "@/server/schemas/reality-logs";
import { realityLogAgentOutputSchema } from "@/server/schemas/agents";

/**
 * Shared Zod schemas for the LangChain chat agent's request and response
 * artifacts. The route, the agent service, and the UI all speak this contract.
 */

export const toolCallStatusSchema = z.enum(["completed", "failed"]);

export const toolCallSchema = z.object({
  name: nonEmptyString,
  status: toolCallStatusSchema
});

/**
 * A reality log draft produced by the agent. It is NOT persisted truth — the
 * user must confirm it through a separate write before it becomes a reality log.
 */
export const realityDraftSchema = realityLogAgentOutputSchema.extend({
  plannedBlockId: uuidSchema
});

export const chatRequestSchema = z.object({
  message: nonEmptyString,
  threadId: z.string().trim().min(1).optional()
});

export const chatStateSchema = z.object({
  goals: z.array(goalSchema),
  plannedBlocks: z.array(plannedBlockSchema),
  realityLogs: z.array(realityLogSchema)
});

export const chatArtifactsSchema = z.object({
  plannedBlocks: z.array(plannedBlockSchema),
  realityDraft: realityDraftSchema.nullable()
});

export const chatResponseSchema = z.object({
  assistantMessage: z.string(),
  toolCalls: z.array(toolCallSchema),
  artifacts: chatArtifactsSchema,
  state: chatStateSchema
});

export type ToolCall = z.infer<typeof toolCallSchema>;
export type RealityDraft = z.infer<typeof realityDraftSchema>;
export type ChatRequest = z.infer<typeof chatRequestSchema>;
export type ChatState = z.infer<typeof chatStateSchema>;
export type ChatArtifacts = z.infer<typeof chatArtifactsSchema>;
export type ChatResponse = z.infer<typeof chatResponseSchema>;

/**
 * Mutable per-request collector. Tools push side effects here as they run so the
 * agent service can surface assistant text plus structured artifacts to the UI.
 */
export type ChatArtifactCollector = {
  toolCalls: ToolCall[];
  createdBlocks: import("@/server/schemas/planned-blocks").PlannedBlock[];
  realityDraft: RealityDraft | null;
};

export const createChatArtifactCollector = (): ChatArtifactCollector => ({
  toolCalls: [],
  createdBlocks: [],
  realityDraft: null
});
