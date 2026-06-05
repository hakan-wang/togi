import { z } from "zod";

const concreteText = z.string().min(8).refine(
  (value) => !["be productive", "productive", "work", "focus"].includes(value.trim().toLowerCase()),
  "Text must be concrete and checkable"
);

export const plannedBlockSchema = z.object({
  title: concreteText,
  start: z.string().datetime(),
  end: z.string().datetime(),
  successCriteria: concreteText,
  category: z.string().min(3)
});

export const plannerOutputSchema = z.object({
  blocks: z.array(plannedBlockSchema).min(1)
});

export const actualCategorySchema = z.object({
  category: z.string().min(3),
  minutes: z.number().nonnegative()
});

export const realityLogInputSchema = z.object({
  plannedBlockId: z.string().min(1),
  actualSummary: z.string().min(12),
  completionScore: z.number().min(0).max(1),
  deviationReason: z.string(),
  actualCategories: z.array(actualCategorySchema),
  confirmedByUser: z.boolean()
});

export const observedActivitySchema = z.object({
  activity: z.string().min(3),
  estimatedMinutes: z.number().nonnegative(),
  confidence: z.number().min(0).max(1)
});

export const screenObservationOutputSchema = z.object({
  blockId: z.string().min(1),
  window: z.string().min(3),
  observedActivities: z.array(observedActivitySchema),
  summary: z.string().min(3)
});

export const coachMessageSchema = z.object({
  message: z.string().min(1),
  proposedCalendarChanges: z.array(plannedBlockSchema).default([])
});

export type PlannerOutput = z.infer<typeof plannerOutputSchema>;
export type RealityLogInput = z.infer<typeof realityLogInputSchema>;
export type ScreenObservationOutput = z.infer<typeof screenObservationOutputSchema>;
export type CoachMessage = z.infer<typeof coachMessageSchema>;
