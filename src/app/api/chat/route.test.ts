import { beforeEach, describe, expect, it, vi } from "vitest";
import type { ChatResponse } from "@/server/services/chat/schemas";

const { runTogiChat } = vi.hoisted(() => ({ runTogiChat: vi.fn() }));
vi.mock("@/server/services/chat/langchain-agent", () => ({ runTogiChat }));

import { POST } from "./route";

const sampleResponse: ChatResponse = {
  assistantMessage: "Planned a 90 minute draft block tomorrow at 09:00.",
  toolCalls: [{ name: "create_planned_block", status: "completed" }],
  artifacts: { plannedBlocks: [], realityDraft: null },
  state: { goals: [], plannedBlocks: [], realityLogs: [] }
};

const authedJsonRequest = (body: unknown) =>
  new Request("http://localhost/api/chat", {
    method: "POST",
    headers: { authorization: "Bearer route-user", "content-type": "application/json" },
    body: JSON.stringify(body)
  });

beforeEach(() => {
  runTogiChat.mockReset();
});

describe("chat route", () => {
  it("runs the agent for an authenticated request and returns the chat response", async () => {
    runTogiChat.mockResolvedValue(sampleResponse);

    const response = await POST(authedJsonRequest({ message: "Plan my morning", threadId: "thread-1" }));

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      assistantMessage: sampleResponse.assistantMessage,
      toolCalls: [{ name: "create_planned_block", status: "completed" }]
    });
    expect(runTogiChat).toHaveBeenCalledWith(
      expect.objectContaining({ userId: "route-user", message: "Plan my morning", threadId: "thread-1" })
    );
  });

  it("rejects unauthenticated requests", async () => {
    const response = await POST(
      new Request("http://localhost/api/chat", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ message: "hi" })
      })
    );

    expect(response.status).toBe(401);
    expect(runTogiChat).not.toHaveBeenCalled();
  });

  it("rejects an empty message with a validation error", async () => {
    const response = await POST(authedJsonRequest({ message: "" }));

    expect(response.status).toBe(400);
    expect(runTogiChat).not.toHaveBeenCalled();
  });
});
