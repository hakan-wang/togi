import OpenAI from "openai";
import { screenObservationOutputSchema, type ScreenObservationOutput } from "@/lib/zod/contracts";

export function buildScreenObserverPrompt() {
  return [
    "You are Bogi Screen Observer Agent.",
    "During a lock-in session, summarize what the screen suggests happened.",
    "Not a coach.",
    "Not a planner.",
    "Not a chat agent.",
    "Just observer.",
    "Return observed activities with estimated minutes and confidence."
  ].join("\n");
}

export function parseScreenObservation(value: unknown): ScreenObservationOutput {
  return screenObservationOutputSchema.parse(value);
}

export async function runScreenObserverAgent(input: {
  blockId: string;
  frames: Array<{ capturedAt: string; imageBase64: string }>;
}): Promise<ScreenObservationOutput> {
  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const response = await client.responses.create({
    model: "gpt-5.4-mini",
    input: [
      { role: "system", content: buildScreenObserverPrompt() },
      { role: "user", content: JSON.stringify({ blockId: input.blockId, frameCount: input.frames.length }) }
    ],
    text: { format: { type: "json_object" } }
  });
  return parseScreenObservation(JSON.parse(response.output_text));
}
