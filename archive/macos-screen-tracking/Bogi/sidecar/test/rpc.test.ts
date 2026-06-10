import { test, expect } from "vitest";
import { LineDecoder, encodeMessage } from "../src/rpc.js";

test("encodeMessage produces one JSON line", () => {
  expect(encodeMessage({ kind: "ready" })).toBe('{"kind":"ready"}\n');
});

test("LineDecoder emits complete messages across chunk boundaries", () => {
  const got: any[] = [];
  const d = new LineDecoder((m) => got.push(m));
  d.push('{"kind":"chat","id":"1","tex');
  d.push('t":"hi","threadId":"t"}\n{"kind":"action_result","id":"2","ok":true}\n');
  expect(got).toEqual([
    { kind: "chat", id: "1", text: "hi", threadId: "t" },
    { kind: "action_result", id: "2", ok: true },
  ]);
});
