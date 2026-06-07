import { test, expect } from "vitest";
import { makeRecordTools } from "../src/tools/recordTools.js";

test("record_segments forwards the segments to the host", async () => {
  const seen: any[] = [];
  const tools = makeRecordTools(async (name, input) => { seen.push({ name, input }); return { ok: true, count: (input as any).segments.length }; });
  const rec = tools.find((t) => t.name === "record_segments")!;
  const out = JSON.parse(await rec.invoke({ segments: [
    { start_at: "2026-06-06T10:00:00Z", end_at: "2026-06-06T10:05:00Z", minutes: 5, cat: "deepwork", sub: "Coding", title: "Editing", on_task: true, confidence: 0.9 },
  ] }));
  expect(out).toEqual({ ok: true, count: 1 });
  expect(seen[0].name).toBe("record_segments");
  expect((seen[0].input as any).segments[0].cat).toBe("deepwork");
});
