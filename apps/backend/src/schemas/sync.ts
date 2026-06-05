import { z } from "zod";

export const RealityLogSyncSchema = z.object({
  id: z.string().min(1),
  blockId: z.string().optional(),
  startAt: z.string().datetime(),
  endAt: z.string().datetime(),
  category: z.string().optional(),
  userText: z.string().min(1),
  generatedSummary: z.string().optional(),
  confidence: z.number().min(0).max(1).optional(),
  source: z.string().min(1)
});
