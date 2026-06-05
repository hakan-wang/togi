import { z } from "zod";
import { nonEmptyString, uuidSchema } from "./common";

export const goalStatusSchema = z.enum(["active", "completed", "archived"]);

export const goalSchema = z.object({
  id: uuidSchema,
  userId: nonEmptyString,
  title: nonEmptyString,
  description: z.string().nullable(),
  status: goalStatusSchema,
  createdAt: z.string(),
  updatedAt: z.string()
});

export const createGoalSchema = z.object({
  title: nonEmptyString,
  description: z.string().trim().optional().nullable()
});

export const updateGoalSchema = createGoalSchema.partial().extend({
  status: goalStatusSchema.optional()
});

export type Goal = z.infer<typeof goalSchema>;
export type CreateGoalInput = z.infer<typeof createGoalSchema>;
export type UpdateGoalInput = z.infer<typeof updateGoalSchema>;
