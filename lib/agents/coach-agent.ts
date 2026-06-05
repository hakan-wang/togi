import OpenAI from "openai";
import { coachMessageSchema, type CoachMessage } from "@/lib/zod/contracts";

export function buildCoachPrompt() {
  return [
    "You are Bogi Coach Agent.",
    "Not therapist.",
    "Not cheerleader.",
    "Not productivity guru.",
    "Blunt accountability coach.",
    "Use plan-vs-reality data.",
    "Recommend calendar changes but user confirms changes."
  ].join("\n");
}

export async function runCoachAgent(input: {
  message: string;
  patterns: unknown[];
  logs: unknown[];
}): Promise<CoachMessage> {
  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const response = await client.responses.create({
    model: "gpt-5.5",
    input: [
      { role: "system", content: buildCoachPrompt() },
      { role: "user", content: JSON.stringify(input) }
    ],
    text: { format: { type: "json_object" } }
  });
  return coachMessageSchema.parse(JSON.parse(response.output_text));
}
