import { Agent, run } from "@openai/agents";
import type { z } from "zod";

export const shouldUseOpenAiAgents = () => Boolean(process.env.OPENAI_API_KEY);

export const runStructuredAgent = async <T extends z.AnyZodObject>(config: {
  name: string;
  instructions: string;
  model: string;
  outputType: T;
  input: unknown;
}): Promise<z.infer<T>> => {
  const agent = new Agent({
    name: config.name,
    instructions: config.instructions,
    model: config.model,
    outputType: config.outputType
  });

  const result = await run(agent, JSON.stringify(config.input), { maxTurns: 2 });
  if (!result.finalOutput) {
    throw new Error(`${config.name} did not return structured output`);
  }

  return result.finalOutput;
};
