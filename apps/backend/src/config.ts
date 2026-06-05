import { z } from "zod";

const EnvSchema = z.object({
  DATABASE_URL: z.string().url().optional(),
  OPENAI_API_KEY: z.string().optional(),
  STRIPE_SECRET_KEY: z.string().optional()
});

export function loadConfig(env: NodeJS.ProcessEnv = process.env) {
  return EnvSchema.parse(env);
}
