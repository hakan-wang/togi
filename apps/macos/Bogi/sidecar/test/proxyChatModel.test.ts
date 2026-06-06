import { test, expect } from "vitest";
import { HumanMessage } from "@langchain/core/messages";
import { BogiProxyChatModel } from "../src/proxyChatModel.js";

test("maps a tool_use response into AIMessage.tool_calls", async () => {
  const calls: any[] = [];
  const model = new BogiProxyChatModel({
    post: async (body) => {
      calls.push(body);
      return {
        text: "",
        stopReason: "tool_use",
        content: [{ type: "tool_use", id: "t1", name: "search_activity", input: { keywords: "x" } }],
      };
    },
  });
  const res = await model.invoke([new HumanMessage("what did I do?")]);
  expect(res.tool_calls?.[0]).toMatchObject({ id: "t1", name: "search_activity", args: { keywords: "x" } });
  expect(calls[0].messages[0]).toMatchObject({ role: "user" });
});

test("maps a plain text response into AIMessage content", async () => {
  const model = new BogiProxyChatModel({
    post: async () => ({ text: "you focused 2h", stopReason: "end_turn", content: [{ type: "text", text: "you focused 2h" }] }),
  });
  const res = await model.invoke([new HumanMessage("summary")]);
  expect(res.content).toBe("you focused 2h");
});
