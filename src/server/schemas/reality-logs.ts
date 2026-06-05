import { z } from "zod";
import { nonEmptyString, uuidSchema } from "./common";

export const realityLogSourceSchema = z.enum(["user", "reality_log_agent"]);

export const realityLogSchema = z.object({
  id: uuidSchema,
  userId: nonEmptyString,
  plannedBlockId: uuidSchema,
  actualSummary: nonEmptyString,
  completionScore: z.number().min(0).max(1),
  deviationReason: z.string(),
  actualCategories: z.array(nonEmptyString),
  confirmedByUser: z.boolean(),
  source: realityLogSourceSchema,
  createdAt: z.string(),
  updatedAt: z.string()
});

export const createRealityLogSchema = z.object({
  plannedBlockId: uuidSchema,
  actualSummary: nonEmptyString,
  completionScore: z.number().min(0).max(1),
  deviationReason: z.string().default(""),
  actualCategories: z.array(nonEmptyString).default([]),
  confirmedByUser: z.boolean(),
  source: realityLogSourceSchema.default("user")
});

export const updateRealityLogSchema = createRealityLogSchema.partial().omit({ plannedBlockId: true });

export type RealityLog = z.infer<typeof realityLogSchema>;
export type CreateRealityLogInput = z.infer<typeof createRealityLogSchema>;
export type UpdateRealityLogInput = z.infer<typeof updateRealityLogSchema>;
