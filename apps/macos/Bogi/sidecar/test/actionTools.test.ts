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
