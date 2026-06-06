import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("../src/lib/supabase.js", () => ({
  verifyJwt: vi.fn(),
  getProfile: vi.fn(),
  setPaidByUserId: vi.fn(),
  setPaidByCustomerId: vi.fn(),
}));

vi.mock("../src/lib/bedrock.js", () => ({
  converse: vi.fn(),
}));

import { handler } from "../src/handler.js";
import { converse } from "../src/lib/bedrock.js";
import { getProfile, verifyJwt } from "../src/lib/supabase.js";
import { UnauthorizedError } from "../src/lib/http.js";
import { makeEvent } from "./helpers.js";

const verifyJwtMock = vi.mocked(verifyJwt);
const getProfileMock = vi.mocked(getProfile);
const converseMock = vi.mocked(converse);

function inferEvent(headers: Record<string, string | undefined>, body: unknown) {
  return makeEvent({
    method: "POST",
    path: "/v1/infer",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

const validBody = {
  messages: [
    { role: "system", content: "You are Bogi." },
    { role: "user", content: "Was I on task?" },
  ],
  max_tokens: 256,
};

beforeEach(() => {
  delete process.env.AUTH_DISABLED;
});

describe("POST /v1/infer", () => {
  it("returns 401 when the Authorization header is missing", async () => {
    const res = await handler(inferEvent({}, validBody));
    expect(res.statusCode).toBe(401);
    expect(verifyJwtMock).not.toHaveBeenCalled();
    expect(converseMock).not.toHaveBeenCalled();
  });

  it("returns 401 when the JWT is invalid", async () => {
    verifyJwtMock.mockRejectedValueOnce(new UnauthorizedError("Invalid or expired token"));
    const res = await handler(inferEvent({ authorization: "Bearer bad.token" }, validBody));
    expect(res.statusCode).toBe(401);
    expect(converseMock).not.toHaveBeenCalled();
  });

  it("returns 402 when the user is authenticated but not paid", async () => {
    verifyJwtMock.mockResolvedValueOnce({ id: "user-1", email: "a@b.com" });
    getProfileMock.mockResolvedValueOnce({ paid: false, plan: null });
    const res = await handler(inferEvent({ authorization: "Bearer good" }, validBody));
    expect(res.statusCode).toBe(402);
    expect(converseMock).not.toHaveBeenCalled();
  });

  it("forwards to Bedrock and returns { text } for a paid user", async () => {
    verifyJwtMock.mockResolvedValueOnce({ id: "user-1", email: "a@b.com" });
    getProfileMock.mockResolvedValueOnce({ paid: true, plan: "pro" });
    converseMock.mockResolvedValueOnce("You stayed on task for 42 minutes.");

    const res = await handler(inferEvent({ authorization: "Bearer good" }, validBody));

    expect(res.statusCode).toBe(200);
    expect(JSON.parse(res.body)).toEqual({ text: "You stayed on task for 42 minutes." });

    expect(converseMock).toHaveBeenCalledTimes(1);
    const call = converseMock.mock.calls[0]![0];
    expect(call.maxTokens).toBe(256);
    expect(call.modelId).toBe("eu.anthropic.claude-sonnet-4-6");
    expect(call.messages).toEqual(validBody.messages);
  });

  it("returns 400 when messages are missing", async () => {
    verifyJwtMock.mockResolvedValueOnce({ id: "user-1", email: "a@b.com" });
    getProfileMock.mockResolvedValue({ paid: true, plan: "pro" });
    const res = await handler(inferEvent({ authorization: "Bearer good" }, { max_tokens: 10 }));
    expect(res.statusCode).toBe(400);
  });

  it("bypasses auth and paid checks when AUTH_DISABLED=1", async () => {
    process.env.AUTH_DISABLED = "1";
    converseMock.mockResolvedValueOnce("dev reply");
    const res = await handler(inferEvent({}, validBody));
    expect(res.statusCode).toBe(200);
    expect(JSON.parse(res.body)).toEqual({ text: "dev reply" });
    expect(verifyJwtMock).not.toHaveBeenCalled();
    expect(getProfileMock).not.toHaveBeenCalled();
  });
});
