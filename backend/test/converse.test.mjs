import test from "node:test";
import assert from "node:assert/strict";
import { buildConverseInput, parseConverseOutput } from "../src/converse.mjs";

test("text-only request is backward compatible", () => {
  const input = buildConverseInput({
    modelId: "m", system: "be kind",
    messages: [{ role: "user", content: "hi" }],
    maxTokens: 100, temperature: 0,
  });
  assert.equal(input.modelId, "m");
  assert.deepEqual(input.system, [{ text: "be kind" }]);
  assert.deepEqual(input.messages, [{ role: "user", content: [{ text: "hi" }] }]);
  assert.equal(input.toolConfig, undefined);
});

test("tools become a Converse toolConfig", () => {
  const tools = [{
    name: "search_activity",
    description: "search",
    input_schema: { type: "object", properties: { q: { type: "string" } }, required: ["q"] },
  }];
  const input = buildConverseInput({
    modelId: "m", messages: [{ role: "user", content: "find" }], tools, maxTokens: 100,
  });
  assert.equal(input.toolConfig.tools[0].toolSpec.name, "search_activity");
  assert.deepEqual(
    input.toolConfig.tools[0].toolSpec.inputSchema.json,
    tools[0].input_schema
  );
});

test("structured content blocks (tool_result) pass through", () => {
  const input = buildConverseInput({
    modelId: "m",
    messages: [
      { role: "user", content: "find" },
      { role: "assistant", content: [{ type: "tool_use", id: "t1", name: "search_activity", input: { q: "x" } }] },
      { role: "user", content: [{ type: "tool_result", tool_use_id: "t1", content: "3 results" }] },
    ],
    maxTokens: 100,
  });
  assert.deepEqual(input.messages[1].content, [
    { toolUse: { toolUseId: "t1", name: "search_activity", input: { q: "x" } } },
  ]);
  assert.deepEqual(input.messages[2].content, [
    { toolResult: { toolUseId: "t1", content: [{ text: "3 results" }] } },
  ]);
});

test("consecutive tool_result user messages are merged into one Converse turn", () => {
  const input = buildConverseInput({
    modelId: "m",
    messages: [
      { role: "user", content: "go" },
      { role: "assistant", content: [
        { type: "tool_use", id: "a", name: "t", input: {} },
        { type: "tool_use", id: "b", name: "t", input: {} },
      ] },
      { role: "user", content: [{ type: "tool_result", tool_use_id: "a", content: "ra" }] },
      { role: "user", content: [{ type: "tool_result", tool_use_id: "b", content: "rb" }] },
    ],
    maxTokens: 100,
  });
  assert.deepEqual(input.messages.map((m) => m.role), ["user", "assistant", "user"]);
  assert.equal(input.messages[2].content.length, 2);
  assert.equal(input.messages[2].content[0].toolResult.toolUseId, "a");
  assert.equal(input.messages[2].content[1].toolResult.toolUseId, "b");
});

test("parseConverseOutput surfaces text, tool_use, stopReason, usage", () => {
  const res = {
    stopReason: "tool_use",
    usage: { inputTokens: 5, outputTokens: 7 },
    output: { message: { role: "assistant", content: [
      { text: "let me look" },
      { toolUse: { toolUseId: "t1", name: "search_activity", input: { q: "x" } } },
    ] } },
  };
  const out = parseConverseOutput(res);
  assert.equal(out.stopReason, "tool_use");
  assert.equal(out.text, "let me look");
  assert.deepEqual(out.content, [
    { type: "text", text: "let me look" },
    { type: "tool_use", id: "t1", name: "search_activity", input: { q: "x" } },
  ]);
  assert.deepEqual(out.usage, { inputTokens: 5, outputTokens: 7 });
});
