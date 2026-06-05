import { describe, expect, it } from "vitest";
import { buildServer } from "../src/server";

describe("sync", () => {
  it("accepts a reality log sync payload", async () => {
    const server = buildServer();
    const response = await server.inject({
      method: "POST",
      url: "/sync/reality-logs",
      payload: {
        id: "log_1",
        startAt: "2026-06-05T10:00:00.000Z",
        endAt: "2026-06-05T10:45:00.000Z",
        userText: "Edited for 45 minutes",
        source: "manual"
      }
    });

    expect(response.statusCode).toBe(202);
    expect(response.json()).toEqual({ accepted: true });
  });
});
