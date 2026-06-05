import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const source = () => readFileSync("src/app/page.tsx", "utf8");

describe("home page", () => {
  it("is a user-facing Togi chat mockup", () => {
    const page = source();

    expect(page).toContain("Togi");
    expect(page).toContain("Ask Togi");
    expect(page).toContain("/api/chat");
    expect(page).toContain("Today");
    expect(page).not.toContain("Run all smoke tests");
    expect(page).not.toContain("Bearer token");
  });
});
