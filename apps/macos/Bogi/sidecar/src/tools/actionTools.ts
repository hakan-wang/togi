import { tool, type StructuredToolInterface } from "@langchain/core/tools";
import { z } from "zod";

export type CallAction = (name: string, input: unknown) => Promise<unknown>;

export function makeActionTools(callAction: CallAction): StructuredToolInterface[] {
  const create_block = tool(
    async (input) => JSON.stringify(await callAction("create_block", input)),
    {
      name: "create_block",
      description: "Create a planned calendar block of focused time. Resolve relative dates/times against the current time before calling.",
      schema: z.object({
        title: z.string().describe("Activity name"),
        start: z.string().describe("ISO-8601 start datetime"),
        end: z.string().describe("ISO-8601 end datetime"),
      }),
    }
  );

  const move_block = tool(
    async (input) => JSON.stringify(await callAction("move_block", input)),
    {
      name: "move_block",
      description: "Move an existing planned block to a new time. Identify it by a title fragment.",
      schema: z.object({
        match: z.string().describe("A fragment of the block title to move"),
        start: z.string().describe("New ISO-8601 start datetime"),
        end: z.string().describe("New ISO-8601 end datetime"),
      }),
    }
  );

  const post_nudge = tool(
    async (input) => JSON.stringify(await callAction("post_nudge", input)),
    {
      name: "post_nudge",
      description: "Show the user a short, kind, supportive nudge when they have drifted off their planned focus. Be specific and honest about the drift but gentle and encouraging. Never use em-dashes.",
      schema: z.object({
        severity: z.number().int().min(0).max(3).describe("0 gentle .. 3 urgent"),
        message: z.string().describe("The nudge text shown above the mascot"),
      }),
    }
  );

  return [create_block, move_block, post_nudge];
}
