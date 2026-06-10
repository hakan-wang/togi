import { test, expect } from "vitest";
import { tool } from "@langchain/core/tools";
import { z } from "zod";
import { createBogiAgent } from "../src/agent.js";

test("agent invokes a tool then answers", async () => {
  const echo = tool(async ({ value }) => `echo:${value}`, {
    name: "echo", description: "Echo the value back.",
    schema: z.object({ value: z.string() }),
  });
  // Fake proxy: first turn asks for the tool, second turn answers with the tool output.
  let turn = 0;
  const agent = createBogiAgent({
    tools: [echo],
    post: async (body) => {
      turn += 1;
      if (turn === 1) {
        return { text: "", stopReason: "tool_use",
          content: [{ type: "tool_use", id: "t1", name: "echo", input: { value: "hi" } }] };
      }
      const toolMsg = JSON.stringify(body.messages.at(-1));
      return { text: `done ${toolMsg.includes("echo:hi") ? "ok" : "no"}`, stopReason: "end_turn",
        content: [{ type: "text", text: `done ${toolMsg.includes("echo:hi") ? "ok" : "no"}` }] };
    },
  });
  const res = await agent.invoke({ messages: [{ role: "user", content: "say hi" }] });
  expect(res.messages.at(-1)?.content).toContain("done ok");
});
