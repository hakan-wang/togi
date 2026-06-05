import OpenAI from "openai";
import { plannerOutputSchema, type PlannerOutput } from "@/lib/zod/contracts";

export function buildPlannerPrompt() {
  return [
    "You are Bogi Planner Agent.",
    "Turn vague intention into concrete calendar blocks.",
    "No vague blocks.",
    "No 'be productive'.",
    "Every block must be checkable.",
    "Return JSON matching the planner output schema."
  ].join("\n");
}

export function parsePlannerOutput(value: unknown): PlannerOutput {
  return plannerOutputSchema.parse(value);
}

export async function runPlannerAgent(input: {
  userRequest: string;
  currentCalendar: unknown[];
  relevantPatterns: unknown[];
}): Promise<PlannerOutput> {
  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const response = await client.responses.create({
    model: "gpt-5.5",
    input: [
      { role: "system", content: buildPlannerPrompt() },
      { role: "user", content: JSON.stringify(input) }
    ],
    text: { format: { type: "json_object" } }
  });
  return parsePlannerOutput(JSON.parse(response.output_text));
}
