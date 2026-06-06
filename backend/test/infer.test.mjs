import test from "node:test";
import assert from "node:assert/strict";
import { buildInferResponse } from "../src/handler.mjs";

test("buildInferResponse returns text, content, stopReason for tool calls", () => {
  const parsed = {
    text: "looking",
    content: [{ type: "tool_use", id: "t1", name: "search_activity", input: { q: "x" } }],
    stopReason: "tool_use",
    usage: { outputTokens: 3 },
  };
  const body = buildInferResponse(parsed);
  assert.equal(body.text, "looking");
  assert.equal(body.stopReason, "tool_use");
  assert.equal(body.content[0].type, "tool_use");
  assert.deepEqual(body.usage, { outputTokens: 3 });
});
