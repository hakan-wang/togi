import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("../src/lib/supabase.js", () => ({
  verifyJwt: vi.fn(),
  getProfile: vi.fn(),
  setPaidByUserId: vi.fn(),
  setPaidByCustomerId: vi.fn(),
}));

import { handler } from "../src/handler.js";
import { getProfile, verifyJwt } from "../src/lib/supabase.js";
import { makeEvent } from "./helpers.js";

const verifyJwtMock = vi.mocked(verifyJwt);
const getProfileMock = vi.mocked(getProfile);

function statusEvent(headers: Record<string, string | undefined>) {
  return makeEvent({ method: "GET", path: "/v1/account/status", headers });
}

beforeEach(() => {
  delete process.env.AUTH_DISABLED;
});

describe("GET /v1/account/status", () => {
  it("returns the paid flag and plan for the authed user", async () => {
    verifyJwtMock.mockResolvedValueOnce({ id: "user-1", email: "a@b.com" });
    getProfileMock.mockResolvedValueOnce({ paid: true, plan: "pro" });

    const res = await handler(statusEvent({ authorization: "Bearer good" }));

    expect(res.statusCode).toBe(200);
    expect(JSON.parse(res.body)).toEqual({ paid: true, plan: "pro" });
    expect(getProfileMock).toHaveBeenCalledWith("user-1");
  });

  it("returns paid=false for an unpaid user", async () => {
    verifyJwtMock.mockResolvedValueOnce({ id: "user-2", email: null });
    getProfileMock.mockResolvedValueOnce({ paid: false, plan: null });

    const res = await handler(statusEvent({ authorization: "Bearer good" }));

    expect(res.statusCode).toBe(200);
    expect(JSON.parse(res.body)).toEqual({ paid: false, plan: null });
  });

  it("returns 401 without a token", async () => {
    const res = await handler(statusEvent({}));
    expect(res.statusCode).toBe(401);
    expect(verifyJwtMock).not.toHaveBeenCalled();
  });
});
