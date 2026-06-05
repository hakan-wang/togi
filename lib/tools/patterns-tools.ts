import { z } from "zod";

export const patternsGetRelevantInput = z.object({
  userId: z.string().min(1),
  category: z.string().min(3)
});

export const patternsUpsertInput = z.object({
  userId: z.string().min(1),
  patternKey: z.string().min(3),
  evidence: z.record(z.string(), z.unknown()),
  recommendation: z.string().min(8)
});
