import { describe, expect, it } from "vitest";
import { BogiToolNameSchema } from "../src/agents/tools";

describe("Bogi tools", () => {
  it("allows owned planning tools", () => {
    expect(BogiToolNameSchema.parse("read_calendar")).toBe("read_calendar");
    expect(BogiToolNameSchema.parse("save_reality_log")).toBe("save_reality_log");
  });
});
