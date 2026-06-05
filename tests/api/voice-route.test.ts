import { describe, expect, it } from "vitest";
import { POST } from "@/app/api/voice/transcribe/route";

describe("voice route", () => {
  it("rejects missing audio files", async () => {
    const response = await POST(new Request("http://127.0.0.1/api/voice/transcribe", {
      method: "POST",
      body: new FormData()
    }));
    expect(response.status).toBe(400);
  });
});
