import { describe, expect, it } from "vitest";
import { POST } from "@/app/api/screen/batch/route";

function frameRequest(fields: Record<string, string>) {
  const form = new FormData();
  for (const [key, value] of Object.entries(fields)) form.append(key, value);
  return new Request("http://127.0.0.1/api/screen/batch", {
    method: "POST",
    body: form
  });
}

describe("screen batch route", () => {
  it("rejects frame uploads without required metadata", async () => {
    const response = await POST(frameRequest({ plannedBlockId: "blk_1" }));
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "missing required frame metadata" });
  });

  it("dedupes uploaded frame hashes", async () => {
    const first = await POST(frameRequest({
      plannedBlockId: "blk_1",
      capturedAt: "2026-06-06T13:00:00.000Z",
      hash: "test_hash_unique"
    }));
    const second = await POST(frameRequest({
      plannedBlockId: "blk_1",
      capturedAt: "2026-06-06T13:00:15.000Z",
      hash: "test_hash_unique"
    }));

    expect(await first.json()).toMatchObject({ accepted: true, plannedBlockId: "blk_1" });
    expect(await second.json()).toEqual({ accepted: false, reason: "duplicate" });
  });
});
