import OpenAI from "openai";
import { realityLogInputSchema, type RealityLogInput } from "@/lib/zod/contracts";

export function buildRealityLogPrompt() {
  return [
    "You are Bogi Reality Log Agent.",
    "Ask user what actually happened.",
    "Reconcile user answer with screen observations.",
    "Screen evidence is not final truth.",
    "User confirmation is the source of truth."
  ].join("\n");
}

export function parseRealityLog(value: unknown): RealityLogInput {
  return realityLogInputSchema.parse(value);
}

export async function runRealityLogAgent(input: {
  plannedBlockId: string;
  plannedTitle: string;
  observationSummary: string;
  userCorrection: string;
}): Promise<RealityLogInput> {
  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const response = await client.responses.create({
    model: "gpt-5.5",
    input: [
      { role: "system", content: buildRealityLogPrompt() },
      { role: "user", content: JSON.stringify(input) }
    ],
    text: { format: { type: "json_object" } }
  });
  return parseRealityLog(JSON.parse(response.output_text));
}
