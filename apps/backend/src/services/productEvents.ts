import { z } from "zod";

const EventNameSchema = z.enum([
  "created_block",
  "completed_reality_log",
  "missed_reality_log",
  "started_lock_in",
  "ended_lock_in",
  "viewed_week_summary",
  "paid_lifetime"
]);

const SensitiveKeys = new Set(["userText", "transcript", "ocrText", "accessibilityText", "screenshot"]);

export const ProductEventSchema = z.object({
  name: EventNameSchema,
  properties: z.record(z.string(), z.string()).superRefine((properties, context) => {
    for (const key of Object.keys(properties)) {
      if (SensitiveKeys.has(key)) {
        context.addIssue({
          code: z.ZodIssueCode.custom,
          message: `Sensitive analytics property is not allowed: ${key}`
        });
      }
    }
  })
});
