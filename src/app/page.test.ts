import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import Home from "./page";

// The initial (empty-thread) render is what a new user first sees.
const html = renderToStaticMarkup(createElement(Home));

describe("user chat page", () => {
  it("frames Togi as a real product experience", () => {
    expect(html).toContain("Togi");
    expect(html).toContain("Plan with intention");
    // A welcoming prompt, suggested prompts, and a composer — the product surface.
    expect(html).toContain("What are you taking on?");
    expect(html).toContain("deep work block");
    expect(html.toLowerCase()).toContain("tell togi");
  });

  it("does not leak developer, transport, or testing-suite framing to the user", () => {
    const forbidden = [
      "Bearer",
      "authorization",
      "/api/chat",
      "/api/reality-logs",
      "toolCalls",
      "assistantMessage",
      "JSON",
      "bearer token",
      "endpoint",
      "smoke",
      "test suite",
      "401"
    ];
    for (const term of forbidden) {
      expect(html).not.toContain(term);
    }
  });
});
