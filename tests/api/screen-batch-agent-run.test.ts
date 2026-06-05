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

describe("screen batch agent run logging", () => {
  it("records successful screen observer agent runs when user id is provided", async () => {
    const form = new FormData();
    form.append("userId", "usr_1");
    form.append("plannedBlockId", "blk_1");
    form.append("screenSessionId", "ses_1");
    form.append("capturedAt", "2026-06-06T13:15:00.000Z");
    form.append("hash", "agent_run_screen_hash_unique");
    form.append("batchReady", "true");
    form.append("timeWindowStart", "2026-06-06T13:00:00.000Z");
    form.append("timeWindowEnd", "2026-06-06T13:15:00.000Z");
    form.append("framesJson", JSON.stringify([{ capturedAt: "2026-06-06T13:00:00.000Z", imageBase64: "abc" }]));

    const response = await POST(new Request("http://127.0.0.1/api/screen/batch", { method: "POST", body: form }));

    expect(mocks.saveAgentRun).toHaveBeenCalledWith({ db: true }, {
      userId: "usr_1",
      agentName: "screen_observer_agent",
      input: {
        blockId: "blk_1",
        frames: [{ capturedAt: "2026-06-06T13:00:00.000Z", imageBase64: "abc" }]
      },
      output: expect.objectContaining({ summary: "Mostly editing." }),
      status: "succeeded"
    });
    expect(await response.json()).toMatchObject({ agentRun: { id: "run_screen" } });
  });
});
