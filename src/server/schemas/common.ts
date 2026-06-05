import { z } from "zod";

export const isoDateTimeSchema = z.string().datetime();
export const nonEmptyString = z.string().trim().min(1);
export const uuidSchema = z.string().uuid();

export const paginationQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(50)
});
