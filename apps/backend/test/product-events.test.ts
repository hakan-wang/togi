import { describe, expect, it } from "vitest";
import { ProductEventSchema } from "../src/services/productEvents";

describe("product events", () => {
  it("allows product event names without sensitive content", () => {
    expect(ProductEventSchema.parse({ name: "created_block", properties: { source: "command_bar" } })).toEqual({
      name: "created_block",
      properties: { source: "command_bar" }
    });
  });

  it("rejects sensitive content properties", () => {
    expect(() =>
      ProductEventSchema.parse({ name: "completed_reality_log", properties: { userText: "private log" } })
    ).toThrow();
  });
});
