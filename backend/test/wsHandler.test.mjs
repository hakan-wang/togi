import test from "node:test";
import assert from "node:assert/strict";
import { streamEventToFrame } from "../src/wsHandler.mjs";

test("contentBlockDelta text -> delta frame", () => {
  assert.deepEqual(
    streamEventToFrame({ contentBlockDelta: { delta: { text: "hel" } } }),
    { type: "delta", text: "hel" }
  );
});
test("toolUse start -> tool_use frame", () => {
  assert.deepEqual(
    streamEventToFrame({ contentBlockStart: { start: { toolUse: { toolUseId: "t1", name: "search_activity" } } } }),
    { type: "tool_use_start", id: "t1", name: "search_activity" }
  );
});
test("messageStop -> stop frame", () => {
  assert.deepEqual(
    streamEventToFrame({ messageStop: { stopReason: "tool_use" } }),
    { type: "stop", stopReason: "tool_use" }
  );
});
test("unknown event -> null", () => {
  assert.equal(streamEventToFrame({ metadata: {} }), null);
});
