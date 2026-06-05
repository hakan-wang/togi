import { z } from "zod";

export const goalsReadInput = z.object({
  userId: z.string().min(1)
});

export const goalsUpdateInput = z.object({
  userId: z.string().min(1),
  goalId: z.string().min(1),
  title: z.string().min(3),
  description: z.string(),
  status: z.enum(["active", "paused", "complete"])
});
