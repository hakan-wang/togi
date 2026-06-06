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

  return [create_block, move_block];
}
