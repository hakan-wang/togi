import { tool, type StructuredToolInterface } from "@langchain/core/tools";
import { z } from "zod";
import { type CallAction } from "./actionTools.js";

const segment = z.object({
  start_at: z.string(), end_at: z.string(), minutes: z.number(),
  category: z.string().nullish(), sub_category: z.string().nullish(), sub_sub: z.string().nullish(),
  on_task: z.boolean().nullish(), confidence: z.number().nullish(),
});

export function makeRecordTools(callAction: CallAction): StructuredToolInterface[] {
  const record_segments = tool(
    async (input) => JSON.stringify(await callAction("record_segments", input)),
    {
      name: "record_segments",
      description: "Persist the labeled time segments you produced from the last few minutes of activity. Call this exactly once per activity review, after segmenting the observations into category / sub_category / sub_sub blocks with minutes and on_task.",
      schema: z.object({ segments: z.array(segment) }),
    }
  );
  return [record_segments];
}
