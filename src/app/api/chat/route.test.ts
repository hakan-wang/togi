import { describe, expect, it } from "vitest";
import { POST } from "./route";

const authedRequest = (body: unknown) =>
  new Request("http://localhost/api/chat", {
    method: "POST",
    headers: {
      authorization: "Bearer chat-user",
      "content-type": "application/json"
    },
    body: JSON.stringify(body)
  });

describe("chat route", () => {
  it("turns planning messages into planned block artifacts", async () => {
    const response = await POST(
      authedRequest({
        message: "Plan one focused block for shipping the backend tomorrow morning"
      })
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      mode: "planner",
      assistantMessage: expect.stringContaining("planned"),
      artifacts: {
        plannedBlocks: [expect.objectContaining({ title: expect.any(String), status: "planned" })]
      }
    });
  });

  it("answers ordinary coaching messages with current state", async () => {
    const response = await POST(
      authedRequest({
        message: "What should I do next?"
      })
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      mode: "coach",
      assistantMessage: expect.any(String),
      state: {
        goals: expect.any(Array),
        plannedBlocks: expect.any(Array),
        realityLogs: expect.any(Array)
      }
    });
  });
});
