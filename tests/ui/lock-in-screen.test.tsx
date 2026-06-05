import { createElement } from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { LockInScreen } from "@/components/lock-in-screen";

function mockMediaStream() {
  return {
    getTracks: () => [{ stop: vi.fn() }]
  } as unknown as MediaStream;
}

describe("LockInScreen", () => {
  const getDisplayMedia = vi.fn();

  beforeEach(() => {
    vi.restoreAllMocks();
    getDisplayMedia.mockReset();
    Object.defineProperty(navigator, "mediaDevices", {
      configurable: true,
      value: { getDisplayMedia }
    });
    vi.spyOn(HTMLMediaElement.prototype, "play").mockResolvedValue(undefined);
  });

  it("starts persisted capture for the demo lock-in user", async () => {
    getDisplayMedia.mockResolvedValue(mockMediaStream());
    const fetchMock = vi.fn(async () => ({
      ok: true,
      json: async () => ({ screenSession: { id: "ses_1" } })
    }));
    vi.stubGlobal("fetch", fetchMock);

    render(createElement(LockInScreen));
    fireEvent.click(screen.getByRole("button", { name: /share screen/i }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith("/api/screen/session", expect.any(Object)));
    const [, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(JSON.parse(String(init.body))).toMatchObject({
      userId: "demo-user",
      plannedBlockId: "demo-block"
    });
  });
});
