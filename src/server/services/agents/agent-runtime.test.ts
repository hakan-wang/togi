import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

describe("agent runtime", () => {
  it("uses the direct OpenAI client instead of the Agents SDK proxy path", () => {
    const source = readFileSync("src/server/services/agents/agent-runtime.ts", "utf8");

    expect(source).toContain('from "node:https"');
    expect(source).not.toContain('from "@openai/agents"');
    expect(source).not.toContain("new OpenAI");
  });
});
