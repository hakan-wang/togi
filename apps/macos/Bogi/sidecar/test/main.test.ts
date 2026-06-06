import { test, expect } from "vitest";
import { makeDispatcher } from "../src/main.js";

test("chat message produces a result line", async () => {
  const out: string[] = [];
  const dispatch = makeDispatcher({
    agent: { invoke: async () => ({ messages: [{ content: "you did great" }] }) } as any,
    write: (line) => out.push(line),
  });
  await dispatch({ kind: "chat", id: "1", threadId: "t1", text: "how was today?" });
  expect(out.join("")).toContain('"kind":"result"');
  expect(out.join("")).toContain("you did great");
});
