import { describe, expect, it } from "vitest";
import { jsonRequest } from "./mock-request";

describe("jsonRequest", () => {
  it("creates a POST JSON request", async () => {
    const request = jsonRequest({ value: "ok" });
    expect(request.method).toBe("POST");
    expect(await request.json()).toEqual({ value: "ok" });
  });
});
