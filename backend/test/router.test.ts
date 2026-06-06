import { describe, expect, it, vi } from "vitest";

vi.mock("../src/lib/supabase.js", () => ({
  verifyJwt: vi.fn(),
  getProfile: vi.fn(),
  setPaidByUserId: vi.fn(),
  setPaidByCustomerId: vi.fn(),
}));

import { handler } from "../src/handler.js";
import { makeEvent } from "./helpers.js";

describe("router", () => {
  it("returns 404 for unknown routes", async () => {
    const res = await handler(makeEvent({ method: "GET", path: "/nope" }));
    expect(res.statusCode).toBe(404);
  });

  it("returns 404 for a known path with the wrong method", async () => {
    const res = await handler(makeEvent({ method: "GET", path: "/v1/infer" }));
    expect(res.statusCode).toBe(404);
  });
});
