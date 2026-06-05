import { describe, expect, it } from "vitest";
import { z } from "zod";
import { jsonValidated } from "./api";

describe("api helpers", () => {
  it("validates response bodies with Zod before returning JSON", async () => {
    const response = jsonValidated(z.object({ ok: z.literal(true) }), { ok: true });

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ ok: true });
  });

  it("returns validation error when response body violates schema", async () => {
    const response = jsonValidated(z.object({ ok: z.literal(true) }), { ok: false });

    expect(response.status).toBe(500);
    await expect(response.json()).resolves.toMatchObject({ error: "Response validation failed" });
  });
});
