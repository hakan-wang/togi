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

  const manage_categories = tool(
    async (input) => JSON.stringify(await callAction("manage_categories", input)),
    {
      name: "manage_categories",
      description: "Curate the user's category list. op 'add' (name, color?, description?), 'rename' (id, name), 'recolor' (id, color), or 'merge' (from, into). merge reassigns that category across ALL the user's past activity, plans, and events, then deletes it, so use it deliberately.",
      schema: z.object({
        op: z.enum(["add", "rename", "recolor", "merge"]),
        id: z.string().nullish(),
        name: z.string().nullish(),
        color: z.string().nullish(),
        description: z.string().nullish(),
        from: z.string().nullish(),
        into: z.string().nullish(),
      }),
    }
  );

  const write_behaviour = tool(
    async (input) => JSON.stringify(await callAction("write_behaviour", input)),
    {
      name: "write_behaviour",
      description: "Save what you have learned about how the user works. REPLACES the whole learned-behaviour note (keep prior insights you still believe). Does not touch their name or north star. Keep it a short bulleted profile.",
      schema: z.object({ text: z.string() }),
    }
  );

  const add_event = tool(
    async (input) => JSON.stringify(await callAction("add_event", input)),
    {
      name: "add_event",
      description: "Record a real-world commitment the user mentions (meeting, gym, appointment). Resolve relative times against the current time. cat, if given, must be an existing category.",
      schema: z.object({
        title: z.string(),
        start: z.string(),
        end: z.string(),
        cat: z.string().nullish(),
        sub: z.string().nullish(),
        desc: z.string().nullish(),
      }),
    }
  );

  return [create_block, move_block, post_nudge, manage_categories, write_behaviour, add_event];
}
