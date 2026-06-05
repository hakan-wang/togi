import { z } from "zod";
import { screenObservationOutputSchema } from "@/lib/zod/contracts";

export const screenSessionStartInput = z.object({
  userId: z.string().min(1),
  plannedBlockId: z.string().min(1),
  rawFramesEnabled: z.boolean().default(false)
});

export const screenObservationAddSummaryInput = screenObservationOutputSchema.extend({
  screenSessionId: z.string().min(1),
  timeWindowStart: z.string().datetime(),
  timeWindowEnd: z.string().datetime()
});
