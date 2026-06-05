import { z } from "zod";
import { isoDateTimeSchema, nonEmptyString, uuidSchema } from "./common";

export const plannedBlockStatusSchema = z.enum(["planned", "completed", "cancelled"]);
export const plannedBlockCreatedBySchema = z.enum(["user", "planner_agent"]);

export const plannedBlockSchema = z.object({
  id: uuidSchema,
  userId: nonEmptyString,
  calendarEventId: z.string().nullable(),
  title: nonEmptyString,
  startTime: isoDateTimeSchema,
  endTime: isoDateTimeSchema,
  intentionText: nonEmptyString,
  successCriteria: z.array(nonEmptyString).min(1),
  category: nonEmptyString,
  status: plannedBlockStatusSchema,
  createdBy: plannedBlockCreatedBySchema,
  createdAt: isoDateTimeSchema,
  updatedAt: isoDateTimeSchema
});

const plannedBlockWriteSchema = z.object({
  calendarEventId: z.string().trim().optional().nullable(),
  title: nonEmptyString,
  startTime: isoDateTimeSchema,
  endTime: isoDateTimeSchema,
  intentionText: nonEmptyString,
  successCriteria: z.array(nonEmptyString).min(1),
  category: nonEmptyString,
  createdBy: plannedBlockCreatedBySchema.default("user")
});

export const createPlannedBlockSchema = plannedBlockWriteSchema.refine(
  (value) => new Date(value.endTime).getTime() > new Date(value.startTime).getTime(),
  {
    message: "endTime must be after startTime",
    path: ["endTime"]
  }
);

export const updatePlannedBlockSchema = plannedBlockWriteSchema.partial().extend({
  status: plannedBlockStatusSchema.optional()
});

export type PlannedBlock = z.infer<typeof plannedBlockSchema>;
export type CreatePlannedBlockInput = z.infer<typeof createPlannedBlockSchema>;
export type UpdatePlannedBlockInput = z.infer<typeof updatePlannedBlockSchema>;
