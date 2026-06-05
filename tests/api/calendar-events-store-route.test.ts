import { describe, expect, it, vi } from "vitest";
import { POST } from "@/app/api/calendar/events/route";

const mocks = vi.hoisted(() => ({
  insertGoogleCalendarEvent: vi.fn(async () => "gcal_evt_1"),
  savePlannedBlock: vi.fn(async () => ({ id: "blk_1", calendar_event_id: "gcal_evt_1" }))
}));

vi.mock("@/lib/calendar/google-calendar", async () => {
  const actual = await vi.importActual<typeof import("@/lib/calendar/google-calendar")>("@/lib/calendar/google-calendar");
  return { ...actual, insertGoogleCalendarEvent: mocks.insertGoogleCalendarEvent };
});

vi.mock("@/lib/db/server", () => ({
  createServerSupabaseClient: vi.fn(async () => ({ db: true }))
}));

vi.mock("@/lib/db/bogi-store", async () => {
  const actual = await vi.importActual<typeof import("@/lib/db/bogi-store")>("@/lib/db/bogi-store");
  return { ...actual, savePlannedBlock: mocks.savePlannedBlock };
});

describe("calendar events route store integration", () => {
  it("creates a Google event and stores the planned block with event id", async () => {
    const response = await POST(new Request("http://127.0.0.1/api/calendar/events", {
      method: "POST",
      body: JSON.stringify({
        userId: "usr_1",
        title: "Edit video",
        start: "2026-06-06T13:00:00.000Z",
        end: "2026-06-06T14:00:00.000Z",
        successCriteria: "Rough cut first 3 minutes",
        category: "work/video"
      })
    }));

    expect(mocks.insertGoogleCalendarEvent).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      title: "Edit video"
    }));
    expect(mocks.savePlannedBlock).toHaveBeenCalledWith({ db: true }, "usr_1", expect.objectContaining({
      title: "Edit video"
    }), "gcal_evt_1");
    expect(await response.json()).toMatchObject({
      googleCalendarEventId: "gcal_evt_1",
      savedBlock: { id: "blk_1" }
    });
  });
});
