import { z } from "zod";
import { plannedBlockSchema } from "@/lib/zod/contracts";

export const calendarReadInput = z.object({
  userId: z.string().min(1),
  start: z.string().datetime(),
  end: z.string().datetime()
});

export const calendarCreateBlockInput = plannedBlockSchema.extend({
  userId: z.string().min(1)
});

export const calendarUpdateBlockInput = calendarCreateBlockInput.extend({
  blockId: z.string().min(1)
});

export const calendarDeleteBlockInput = z.object({
  userId: z.string().min(1),
  blockId: z.string().min(1)
});
