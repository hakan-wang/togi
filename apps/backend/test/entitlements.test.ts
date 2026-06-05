import { describe, expect, it } from "vitest";
import { deriveEntitlement } from "../src/payments/entitlements";

describe("entitlements", () => {
  it("marks paid lifetime customers active", () => {
    expect(deriveEntitlement({ paymentStatus: "paid", product: "lifetime" })).toEqual({
      plan: "lifetime",
      active: true
    });
  });
});
