import { describe, expect, it } from "vitest";
import { services } from "@/server/services/container";
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

  it("falls back to a local plan when the live planner is unavailable", async () => {
    const originalPlan = services.plannerAgent.plan;
    services.plannerAgent.plan = async () => {
      throw new Error("429 codex-lb is temporarily overloaded in the proxy_http lane");
    };

    try {
      const response = await POST(
        authedRequest({
          message: "Plan one focused block even if the live model is overloaded"
        })
      );

      expect(response.status).toBe(200);
      await expect(response.json()).resolves.toMatchObject({
        mode: "planner",
        assistantMessage: expect.stringContaining("planned"),
        artifacts: {
          plannedBlocks: [expect.objectContaining({ title: "Focused work block" })]
        }
      });
    } finally {
      services.plannerAgent.plan = originalPlan;
    }
  });
});
