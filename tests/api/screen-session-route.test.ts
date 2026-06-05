import { describe, expect, it, vi } from "vitest";
import { PATCH, POST } from "@/app/api/screen/session/route";

const mocks = vi.hoisted(() => ({
  startScreenSession: vi.fn(async () => ({ id: "ses_1" })),
  endScreenSession: vi.fn(async () => ({ id: "ses_1", ended_at: "2026-06-06T14:00:00.000Z" }))
}));

vi.mock("@/lib/db/server", () => ({
  createServerSupabaseClient: vi.fn(async () => ({ db: true }))
}));

vi.mock("@/lib/db/bogi-store", async () => {
  const actual = await vi.importActual<typeof import("@/lib/db/bogi-store")>("@/lib/db/bogi-store");
  return {
    ...actual,
    startScreenSession: mocks.startScreenSession,
    endScreenSession: mocks.endScreenSession
  };
});

describe("screen session route", () => {
  it("starts lock-in screen sessions", async () => {
    const response = await POST(new Request("http://127.0.0.1/api/screen/session", {
      method: "POST",
      body: JSON.stringify({
        userId: "usr_1",
        plannedBlockId: "blk_1",
        captureSurface: "browser",
        rawFramesEnabled: false
      })
    }));

    expect(mocks.startScreenSession).toHaveBeenCalledWith({ db: true }, {
      userId: "usr_1",
      plannedBlockId: "blk_1",
      captureSurface: "browser",
      rawFramesEnabled: false
    });
    expect(await response.json()).toEqual({ screenSession: { id: "ses_1" } });
  });

  it("ends lock-in screen sessions", async () => {
    const response = await PATCH(new Request("http://127.0.0.1/api/screen/session", {
      method: "PATCH",
      body: JSON.stringify({
        screenSessionId: "ses_1",
        endedAt: "2026-06-06T14:00:00.000Z"
      })
    }));

    expect(mocks.endScreenSession).toHaveBeenCalledWith({ db: true }, "ses_1", "2026-06-06T14:00:00.000Z");
    expect(await response.json()).toEqual({
      screenSession: { id: "ses_1", ended_at: "2026-06-06T14:00:00.000Z" }
    });
  });
});
