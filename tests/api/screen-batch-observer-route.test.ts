import { describe, expect, it, vi } from "vitest";
import { POST } from "@/app/api/screen/batch/route";

const mocks = vi.hoisted(() => ({
  runScreenObserverAgent: vi.fn(async () => ({
    blockId: "blk_1",
    window: "13:00-13:15",
    observedActivities: [{ activity: "video editing", estimatedMinutes: 12, confidence: 0.82 }],
    summary: "Mostly editing."
  })),
  saveScreenFrameBatch: vi.fn(async () => ({ id: "frame_batch_1" })),
  saveScreenObservationSummary: vi.fn(async () => ({ id: "obs_1" })),
  saveAgentRun: vi.fn(async () => ({ id: "run_screen" }))
}));

vi.mock("@/lib/agents/screen-observer-agent", () => ({
  runScreenObserverAgent: mocks.runScreenObserverAgent
}));

vi.mock("@/lib/db/server", () => ({
  createServerSupabaseClient: vi.fn(async () => ({ db: true }))
}));

vi.mock("@/lib/db/bogi-store", async () => {
  const actual = await vi.importActual<typeof import("@/lib/db/bogi-store")>("@/lib/db/bogi-store");
  return {
    ...actual,
    saveScreenFrameBatch: mocks.saveScreenFrameBatch,
    saveScreenObservationSummary: mocks.saveScreenObservationSummary,
    saveAgentRun: mocks.saveAgentRun
  };
});

function batchReadyRequest() {
  const form = new FormData();
  form.append("userId", "usr_1");
  form.append("plannedBlockId", "blk_1");
  form.append("screenSessionId", "ses_1");
  form.append("capturedAt", "2026-06-06T13:15:00.000Z");
  form.append("hash", "observer_hash_unique");
  form.append("batchReady", "true");
  form.append("timeWindowStart", "2026-06-06T13:00:00.000Z");
  form.append("timeWindowEnd", "2026-06-06T13:15:00.000Z");
  form.append("framesJson", JSON.stringify([{ capturedAt: "2026-06-06T13:00:00.000Z", imageBase64: "abc" }]));
  return new Request("http://127.0.0.1/api/screen/batch", { method: "POST", body: form });
}

describe("screen batch observer route", () => {
  it("runs observer and persists summary when batch is ready", async () => {
    const response = await POST(batchReadyRequest());

    expect(mocks.runScreenObserverAgent).toHaveBeenCalledWith({
      blockId: "blk_1",
      frames: [{ capturedAt: "2026-06-06T13:00:00.000Z", imageBase64: "abc" }]
    });
    expect(mocks.saveScreenObservationSummary).toHaveBeenCalledWith({ db: true }, {
      plannedBlockId: "blk_1",
      screenSessionId: "ses_1",
      timeWindowStart: "2026-06-06T13:00:00.000Z",
      timeWindowEnd: "2026-06-06T13:15:00.000Z",
      observation: expect.objectContaining({ summary: "Mostly editing." })
    });
    expect(await response.json()).toMatchObject({
      observationSummary: { summary: "Mostly editing." },
      savedObservationSummary: { id: "obs_1" },
      agentRun: { id: "run_screen" }
    });
  });
});
