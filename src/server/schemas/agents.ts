import { z } from "zod";
import { isoDateTimeSchema, nonEmptyString, uuidSchema } from "./common";

export const agentRunSchema = z.object({
  id: uuidSchema,
  userId: nonEmptyString,
  agentName: nonEmptyString,
  inputJson: z.unknown(),
  outputJson: z.unknown().nullable(),
  status: z.enum(["started", "completed", "failed"]),
  error: z.string().nullable(),
  model: nonEmptyString,
  startedAt: isoDateTimeSchema,
  completedAt: isoDateTimeSchema.nullable()
});

export const plannerAgentInputSchema = z.object({
  request: nonEmptyString,
  calendarAvailability: z
    .array(
      z.object({
        startTime: isoDateTimeSchema,
        endTime: isoDateTimeSchema
      })
    )
    .min(1),
  activeGoals: z.array(
    z.object({
      id: z.string(),
      title: nonEmptyString,
      status: nonEmptyString
    })
  ),
  userPatterns: z.array(
    z.object({
      patternType: nonEmptyString,
      recommendation: nonEmptyString,
      confidence: z.number().min(0).max(1)
    })
  )
});

export const plannerBlockDraftSchema = z.object({
  title: nonEmptyString,
  startTime: isoDateTimeSchema,
  endTime: isoDateTimeSchema,
  intentionText: nonEmptyString,
  successCriteria: z.array(nonEmptyString).min(1),
  category: nonEmptyString
});

export const plannerAgentOutputSchema = z.object({
  blocks: z.array(plannerBlockDraftSchema).min(1),
  coachingNote: z.string()
});

export const realityLogAgentInputSchema = z.object({
  plannedBlock: z.object({
    id: z.string(),
    title: nonEmptyString,
    intentionText: nonEmptyString,
    successCriteria: z.array(nonEmptyString).min(1)
  }),
  userAnswer: nonEmptyString,
  historicalContext: z.array(z.string()).default([])
});

export const realityLogAgentOutputSchema = z.object({
  actualSummary: nonEmptyString,
  completionScore: z.number().min(0).max(1),
  actualCategories: z.array(nonEmptyString),
  deviationReason: z.string(),
  clarificationQuestion: z.string().nullable(),
  confirmedByUser: z.boolean()
});

export type AgentRun = z.infer<typeof agentRunSchema>;
export type PlannerAgentInput = z.infer<typeof plannerAgentInputSchema>;
export type PlannerAgentOutput = z.infer<typeof plannerAgentOutputSchema>;
export type RealityLogAgentInput = z.infer<typeof realityLogAgentInputSchema>;
export type RealityLogAgentOutput = z.infer<typeof realityLogAgentOutputSchema>;
