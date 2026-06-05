import { describe, expect, it, vi } from "vitest";
import { POST } from "@/app/api/screen/batch/route";
import { frameBatchReadyEvent } from "@/lib/workflows/frame-batch-ready";

const mocks = vi.hoisted(() => ({
  saveScreenFrameBatch: vi.fn(async () => undefined)
}));

vi.mock("@/lib/db/server", () => ({
  createServerSupabaseClient: vi.fn(async () => ({ db: true }))
}));

vi.mock("@/lib/db/bogi-store", async () => {
  const actual = await vi.importActual<typeof import("@/lib/db/bogi-store")>("@/lib/db/bogi-store");
  return {
    ...actual,
    saveScreenFrameBatch: mocks.saveScreenFrameBatch
  };
});

function frameRequest(fields: Record<string, string>) {
  const form = new FormData();
  for (const [key, value] of Object.entries(fields)) form.append(key, value);
  return new Request("http://127.0.0.1/api/screen/batch", {
    method: "POST",
    body: form
  });
}

describe("screen batch route store integration", () => {
  it("stores metadata and returns the frame-batch workflow event", async () => {
    const response = await POST(frameRequest({
      userId: "usr_1",
      plannedBlockId: "blk_1",
      screenSessionId: "ses_1",
      capturedAt: "2026-06-06T13:00:00.000Z",
      hash: "store_hash_unique"
    }));

    expect(mocks.saveScreenFrameBatch).toHaveBeenCalledWith({ db: true }, {
      userId: "usr_1",
      plannedBlockId: "blk_1",
      screenSessionId: "ses_1",
      capturedAt: "2026-06-06T13:00:00.000Z",
      hash: "store_hash_unique"
    });
    expect(await response.json()).toMatchObject({
      accepted: true,
      workflowEvent: frameBatchReadyEvent
    });
  });
});
