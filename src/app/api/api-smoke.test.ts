import { describe, expect, it } from "vitest";
import { GET as health } from "./health/route";
import { POST as createGoal } from "./goals/route";
import { POST as createPlannedBlock } from "./planned-blocks/route";

const authedJsonRequest = (body: unknown) =>
  new Request("http://localhost/api/test", {
    method: "POST",
    headers: {
      authorization: "Bearer api-user",
      "content-type": "application/json"
    },
    body: JSON.stringify(body)
  });

describe("api smoke", () => {
  it("health endpoint returns service status", async () => {
    const response = await health();
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({ ok: true, service: "togi-backend" });
  });

  it("goal endpoint creates goals for bearer user", async () => {
    const response = await createGoal(authedJsonRequest({ title: "Ship launch" }));
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({ userId: "api-user", title: "Ship launch" });
  });

  it("planned block endpoint rejects vague plans", async () => {
    const response = await createPlannedBlock(
      authedJsonRequest({
        title: "Be productive",
        startTime: "2026-06-05T09:00:00.000Z",
        endTime: "2026-06-05T10:00:00.000Z",
        intentionText: "be productive",
        successCriteria: [],
        category: "work"
      })
    );

    expect(response.status).toBe(400);
  });
});
