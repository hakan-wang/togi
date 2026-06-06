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

test("per-request token is surfaced via setToken before invoke", async () => {
  let seen: string | undefined = "unset";
  const dispatch = makeDispatcher({
    agent: { invoke: async () => ({ messages: [{ content: "ok" }] }) } as any,
    write: () => {},
    setToken: (t) => { seen = t; },
  });
  await dispatch({ kind: "chat", id: "1", threadId: "t1", text: "hi", token: "fresh-token" });
  expect(seen).toBe("fresh-token");
});

test("serialized dispatch runs requests one at a time (no activeRequestId interleave)", async () => {
  // Model with a single shared activeRequestId, mirroring BogiProxyChatModel.
  const model = { activeRequestId: null as string | null };
  const order: string[] = [];
  const agent = {
    __bogiModel: model,
    invoke: async () => {
      const id = model.activeRequestId;
      order.push(`start:${id}`);
      // Yield to the event loop; if dispatch were not serialized, the second
      // request would overwrite activeRequestId here before this one finishes.
      await new Promise<void>((r) => setTimeout(r, 0));
      order.push(`end:${id}`);
      return { messages: [{ content: "x" }] };
    },
  };
  const dispatch = makeDispatcher({ agent: agent as any, write: () => {} });

  // Same serialization the stdio loop uses.
  let pending: Promise<void> = Promise.resolve();
  const enqueue = (m: any) => { pending = pending.then(() => dispatch(m)).catch(() => {}); };
  enqueue({ kind: "chat", id: "A", threadId: "t", text: "a" });
  enqueue({ kind: "judge", id: "B", threadId: "t", text: "b" });
  await pending;

  // A must fully complete (start+end with id A) before B starts.
  expect(order).toEqual(["start:A", "end:A", "start:B", "end:B"]);
});
