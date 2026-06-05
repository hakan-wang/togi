import { describe, expect, it } from "vitest";
import { buildOpenAIPlannerRequest } from "../src/agents/openaiPlannerRequest";

describe("OpenAI planner request", () => {
  it("uses structured output and avoids raw screen data", () => {
    const request = buildOpenAIPlannerRequest({
      userQuestion: "What should I plan tomorrow?",
      retrievedContext: "Completed 60 minute editing blocks more reliably than 180 minute blocks."
    });

    expect(request.model).toBe("gpt-4.1");
    expect(request.input).toContain("Do not request raw continuous screen data.");
    expect(request.text.format.type).toBe("json_schema");
  });
});
