import { describe, expect, it } from "vitest";
import { GET } from "@/app/api/summaries/route";

describe("summaries route", () => {
  it("returns requested summary scope", async () => {
    const response = await GET(new Request("http://127.0.0.1/api/summaries?scope=week"));
    expect(await response.json()).toMatchObject({ scope: "week" });
  });
});
