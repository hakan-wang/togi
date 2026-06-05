import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const source = () => readFileSync("src/app/test-console/page.tsx", "utf8");

describe("test console page", () => {
  it("covers every implemented backend feature group", () => {
    const page = source();

    for (const label of [
      "Health",
      "Goals",
      "Planned Blocks",
      "Reality Logs",
      "Agents",
      "Patterns",
      "Google Calendar"
    ]) {
      expect(page).toContain(label);
    }

    for (const route of [
      "/api/health",
      "/api/goals",
      "/api/planned-blocks",
      "/api/reality-logs",
      "/api/agents/planner",
      "/api/agents/reality-log",
      "/api/agents/coach",
      "/api/patterns",
      "/api/calendar/google/connect",
      "/api/calendar/google/callback?code=test-code",
      "/api/calendar/google/sync"
    ]) {
      expect(page).toContain(route);
    }
  });
});
