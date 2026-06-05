import { describe, expect, it } from "vitest";
import { POST as coach } from "./agents/coach/route";
import { POST as planner } from "./agents/planner/route";
import { POST as realityAgent } from "./agents/reality-log/route";
import { GET as calendarCallback } from "./calendar/google/callback/route";
import { GET as calendarConnect } from "./calendar/google/connect/route";
import { POST as calendarSync } from "./calendar/google/sync/route";
import { GET as listGoals, POST as createGoal } from "./goals/route";
import { PATCH as patchGoal } from "./goals/[id]/route";
import { GET as listPatterns } from "./patterns/route";
import { GET as getBlock, PATCH as patchBlock, DELETE as deleteBlock } from "./planned-blocks/[id]/route";
import { GET as listBlocks, POST as createBlock } from "./planned-blocks/route";
import { GET as getRealityLog, PATCH as patchRealityLog } from "./reality-logs/[id]/route";
import { GET as listRealityLogs, POST as createRealityLog } from "./reality-logs/route";

const authedJsonRequest = (body: unknown, method = "POST") =>
  new Request("http://localhost/api/test", {
    method,
    headers: {
      authorization: "Bearer route-user",
      "content-type": "application/json"
    },
    body: JSON.stringify(body)
  });

const authedGetRequest = () =>
  new Request("http://localhost/api/test", {
    headers: {
      authorization: "Bearer route-user"
    }
  });

const authedGetUrl = (url: string) =>
  new Request(url, {
    headers: {
      authorization: "Bearer route-user"
    }
  });

const params = (id: string) => ({ params: Promise.resolve({ id }) });

describe("api route handlers", () => {
  it("supports goal create, list, and patch", async () => {
    const created = await createGoal(authedJsonRequest({ title: "Improve planning" }));
    const goal = await created.json();

    expect(goal.title).toBe("Improve planning");

    const listed = await listGoals(authedGetRequest());
    expect(await listed.json()).toEqual(expect.arrayContaining([expect.objectContaining({ id: goal.id })]));

    const patched = await patchGoal(authedJsonRequest({ status: "completed" }, "PATCH"), params(goal.id));
    await expect(patched.json()).resolves.toMatchObject({ id: goal.id, status: "completed" });
  });

  it("supports planned block create, list, get, patch, and delete", async () => {
    const created = await createBlock(
      authedJsonRequest({
        title: "Write review notes",
        startTime: "2026-06-05T09:00:00.000Z",
        endTime: "2026-06-05T10:00:00.000Z",
        intentionText: "Write review notes for backend checkpoint",
        successCriteria: ["Write three concrete findings"],
        category: "work"
      })
    );
    const block = await created.json();

    expect((await listBlocks(authedGetRequest())).status).toBe(200);
    await expect((await getBlock(authedGetRequest(), params(block.id))).json()).resolves.toMatchObject({ id: block.id });

    const patched = await patchBlock(authedJsonRequest({ status: "completed" }, "PATCH"), params(block.id));
    await expect(patched.json()).resolves.toMatchObject({ id: block.id, status: "completed" });

    const deleted = await deleteBlock(authedGetRequest(), params(block.id));
    expect(await deleted.json()).toEqual({ ok: true });
  });

  it("supports reality log create, list, get, and patch", async () => {
    const blockResponse = await createBlock(
      authedJsonRequest({
        title: "Draft calendar plan",
        startTime: "2026-06-05T11:00:00.000Z",
        endTime: "2026-06-05T12:00:00.000Z",
        intentionText: "Draft calendar plan for tomorrow",
        successCriteria: ["Create one calendar-ready plan"],
        category: "planning"
      })
    );
    const block = await blockResponse.json();
    const created = await createRealityLog(
      authedJsonRequest({
        plannedBlockId: block.id,
        actualSummary: "Created the plan and noted one risk.",
        completionScore: 0.9,
        deviationReason: "Minor missing detail.",
        actualCategories: ["planning"],
        confirmedByUser: true
      })
    );
    const log = await created.json();

    expect((await listRealityLogs(authedGetRequest())).status).toBe(200);
    await expect((await getRealityLog(authedGetRequest(), params(log.id))).json()).resolves.toMatchObject({ id: log.id });

    const patched = await patchRealityLog(authedJsonRequest({ completionScore: 1 }, "PATCH"), params(log.id));
    await expect(patched.json()).resolves.toMatchObject({ id: log.id, completionScore: 1 });
  });

  it("supports planner, reality-log, and coach agent endpoints with agent run logging", async () => {
    const plannerResponse = await planner(
      authedJsonRequest({
        request: "be productive tomorrow",
        calendarAvailability: [{ startTime: "2026-06-06T09:00:00.000Z", endTime: "2026-06-06T10:00:00.000Z" }],
        activeGoals: [{ id: "goal-x", title: "Ship backend", status: "active" }],
        userPatterns: []
      })
    );
    await expect(plannerResponse.json()).resolves.toMatchObject({ blocks: [expect.objectContaining({ category: "planning" })] });

    const realityResponse = await realityAgent(
      authedJsonRequest({
        plannedBlock: {
          id: "block-x",
          title: "Draft notes",
          intentionText: "Draft notes",
          successCriteria: ["Write notes", "Send notes"]
        },
        userAnswer: "I wrote notes but did not send notes.",
        historicalContext: []
      })
    );
    await expect(realityResponse.json()).resolves.toMatchObject({ confirmedByUser: false });

    const coachResponse = await coach(authedJsonRequest({ question: "What should I plan next?" }));
    await expect(coachResponse.json()).resolves.toMatchObject({ evidence: expect.any(Array) });
  });

  it("supports patterns and google calendar boundary endpoints", async () => {
    await expect((await listPatterns(authedGetRequest())).json()).resolves.toEqual(expect.any(Array));
    await expect((await calendarConnect(authedGetRequest())).json()).resolves.toMatchObject({ provider: "google" });
    await expect((await calendarCallback(authedGetUrl("http://localhost/api/calendar/google/callback?code=test-code"))).json()).resolves.toMatchObject({
      status: "callback_received"
    });
    await expect((await calendarSync(authedJsonRequest({}))).json()).resolves.toEqual({ synced: 0 });
  });
});
