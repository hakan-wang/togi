import { tool, type StructuredToolInterface } from "@langchain/core/tools";
import { z } from "zod";
import { type CallAction } from "./actionTools.js";

const segment = z.object({
  start_at: z.string(), end_at: z.string(), minutes: z.number(),
  cat: z.string().nullish(), sub: z.string().nullish(), title: z.string().nullish(), desc: z.string().nullish(),
  on_task: z.boolean().nullish(), confidence: z.number().nullish(),
});

export function makeRecordTools(callAction: CallAction): StructuredToolInterface[] {
  const record_segments = tool(
    async (input) => JSON.stringify(await callAction("record_segments", input)),
    {
      name: "record_segments",
      description: "Persist the labeled time segments you produced from the last few minutes of activity. Call this exactly once per activity review, after segmenting the observations into cat / sub / title / desc blocks with minutes and on_task.",
      schema: z.object({ segments: z.array(segment) }),
    }
  );
  return [record_segments];
}
