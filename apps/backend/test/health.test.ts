import { describe, expect, it } from "vitest";
import { buildServer } from "../src/server";

describe("health", () => {
  it("returns ok", async () => {
    const server = buildServer();
    const response = await server.inject({ method: "GET", url: "/health" });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ ok: true });
  });
});
