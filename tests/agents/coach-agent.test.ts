import { describe, expect, it } from "vitest";
import { buildCoachPrompt } from "@/lib/agents/coach-agent";

describe("coach agent", () => {
  it("uses blunt accountability tone", () => {
    const prompt = buildCoachPrompt();
    expect(prompt).toContain("Not therapist");
    expect(prompt).toContain("Not cheerleader");
    expect(prompt).toContain("Blunt accountability coach");
  });
});
