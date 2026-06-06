import { test, expect } from "vitest";
import { SystemMessage, HumanMessage } from "@langchain/core/messages";
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

test("system messages are not sent as user turns (Converse needs alternating roles)", async () => {
  let captured: any;
  const model = new BogiProxyChatModel({
    post: async (body) => { captured = body; return { text: "ok", stopReason: "end_turn", content: [{ type: "text", text: "ok" }] }; },
    system: "PERSONA",
  });
  await model.invoke([new SystemMessage("PERSONA"), new HumanMessage("hi")]);
  const roles = captured.messages.map((m: any) => m.role);
  expect(roles).toEqual(["user"]); // the system message must be filtered out, not mapped to user
});

test("streams text deltas via onToken and returns accumulated content", async () => {
  const deltas: string[] = [];
  const model = new BogiProxyChatModel({
    // fake streaming transport: yields two text deltas then stop
    stream: async function* () {
      yield { type: "delta", text: "Hello " };
      yield { type: "delta", text: "there" };
      yield { type: "stop", stopReason: "end_turn" };
    },
    onToken: (t) => deltas.push(t),
  });
  const res = await model.invoke([new HumanMessage("hi")]);
  expect(deltas).toEqual(["Hello ", "there"]);
  expect(res.content).toBe("Hello there");
});
