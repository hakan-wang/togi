import { z } from "zod";

export const summariesGetDayInput = z.object({
  userId: z.string().min(1),
  day: z.string().date()
});

export const summariesGetWeekInput = z.object({
  userId: z.string().min(1),
  weekStart: z.string().date()
});
