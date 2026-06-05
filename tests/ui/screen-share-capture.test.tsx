import { createElement } from "react";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ScreenShareCapture } from "@/components/screen-share-capture";

function mockMediaStream() {
  const stop = vi.fn();
  return {
    stop,
    stream: {
      getTracks: () => [{ stop }]
    } as unknown as MediaStream
  };
}

describe("ScreenShareCapture", () => {
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

  it("starts a persisted screen session after media permission succeeds", async () => {
    getDisplayMedia.mockResolvedValue(mockMediaStream().stream);
    const fetchMock = vi.fn(async () => ({
      ok: true,
      json: async () => ({ screenSession: { id: "ses_1" } })
    }));
    vi.stubGlobal("fetch", fetchMock);

    render(createElement(ScreenShareCapture, { plannedBlockId: "blk_1", userId: "usr_1" }));
    fireEvent.click(screen.getByRole("button", { name: /share screen/i }));

    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith("/api/screen/session", expect.any(Object)));
    expect(getDisplayMedia).toHaveBeenCalledWith({ video: true, audio: false });
    const [, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(JSON.parse(String(init.body))).toEqual({
      userId: "usr_1",
      plannedBlockId: "blk_1",
      captureSurface: "browser",
      rawFramesEnabled: false
    });
    expect(await screen.findByText("sharing")).toBeInTheDocument();
  });

  it("does not create a session if media permission is denied", async () => {
    getDisplayMedia.mockRejectedValue(new Error("denied"));
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    render(createElement(ScreenShareCapture, { plannedBlockId: "blk_1", userId: "usr_1" }));
    fireEvent.click(screen.getByRole("button", { name: /share screen/i }));

    expect(await screen.findByText("failed")).toBeInTheDocument();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("keeps sharing when session persistence fails", async () => {
    const media = mockMediaStream();
    getDisplayMedia.mockResolvedValue(media.stream);
    vi.stubGlobal("fetch", vi.fn(async () => ({
      ok: false,
      json: async () => ({ error: "missing supabase env" })
    })));

    render(createElement(ScreenShareCapture, { plannedBlockId: "blk_1", userId: "usr_1" }));
    fireEvent.click(screen.getByRole("button", { name: /share screen/i }));

    expect(await screen.findByText("sharing")).toBeInTheDocument();
    expect(media.stop).not.toHaveBeenCalled();
  });
});
