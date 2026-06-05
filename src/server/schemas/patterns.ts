import { z } from "zod";
import { nonEmptyString, uuidSchema } from "./common";

export const userPatternSchema = z.object({
  id: uuidSchema,
  userId: nonEmptyString,
  patternType: nonEmptyString,
  evidenceJson: z.unknown(),
  recommendation: nonEmptyString,
  confidence: z.number().min(0).max(1),
  createdAt: z.string(),
  updatedAt: z.string()
});

export type UserPattern = z.infer<typeof userPatternSchema>;
