import { test, expect } from "vitest";
import { makeActionTools } from "../src/tools/actionTools.js";

test("create_block emits an action call and returns its result", async () => {
  const seen: any[] = [];
  const tools = makeActionTools(async (name, input) => { seen.push({ name, input }); return { ok: true, id: "blk1" }; });
  const create = tools.find((t) => t.name === "create_block")!;
  const out = JSON.parse(await create.invoke({ title: "Edit video", start: "2026-06-07T15:00:00Z", end: "2026-06-07T16:00:00Z" }));
  expect(out).toEqual({ ok: true, id: "blk1" });
  expect(seen[0].name).toBe("create_block");
  expect(seen[0].input.title).toBe("Edit video");
});

test("post_nudge emits an action call", async () => {
  const seen: any[] = [];
  const tools = makeActionTools(async (name, input) => { seen.push({ name, input }); return { ok: true }; });
  const nudge = tools.find((t) => t.name === "post_nudge")!;
  const out = JSON.parse(await nudge.invoke({ severity: 2, message: "Gently, you drifted to X. Want to refocus?" }));
  expect(out).toEqual({ ok: true });
  expect(seen[0].name).toBe("post_nudge");
  expect(seen[0].input.severity).toBe(2);
});

test("manage_categories forwards op + args", async () => {
  const seen: any[] = [];
  const tools = makeActionTools(async (name, input) => { seen.push({ name, input }); return { ok: true }; });
  const out = JSON.parse(await tools.find((t) => t.name === "manage_categories")!.invoke({ op: "merge", from: "scroll", into: "social" }));
  expect(out).toEqual({ ok: true });
  expect(seen[0].name).toBe("manage_categories");
  expect(seen[0].input.op).toBe("merge");
});

test("write_behaviour + add_event forward", async () => {
  const seen: any[] = [];
  const tools = makeActionTools(async (name, input) => { seen.push({ name, input }); return { ok: true }; });
  await tools.find((t) => t.name === "write_behaviour")!.invoke({ text: "learns fast" });
  await tools.find((t) => t.name === "add_event")!.invoke({ title: "Gym", start: "2026-06-06T18:00:00Z", end: "2026-06-06T19:00:00Z", cat: "health" });
  expect(seen.map((s) => s.name)).toEqual(["write_behaviour", "add_event"]);
});
