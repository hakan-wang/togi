import { describe, expect, it, vi } from "vitest";

const { sendMock } = vi.hoisted(() => ({ sendMock: vi.fn() }));

vi.mock("@aws-sdk/client-bedrock-runtime", () => ({
  BedrockRuntimeClient: vi.fn(() => ({ send: sendMock })),
  ConverseCommand: vi.fn((input: unknown) => ({ input })),
}));

import { converse } from "../src/lib/bedrock.js";
import { ConverseCommand } from "@aws-sdk/client-bedrock-runtime";

const ConverseCommandMock = vi.mocked(ConverseCommand);

describe("converse()", () => {
  it("extracts system messages and maps user/assistant turns, returning joined text", async () => {
    sendMock.mockResolvedValueOnce({
      output: { message: { content: [{ text: "Hello" }, { text: " world" }] } },
    });

    const text = await converse({
      modelId: "eu.anthropic.claude-sonnet-4-6",
      maxTokens: 128,
      messages: [
        { role: "system", content: "You are Bogi." },
        { role: "user", content: "Hi" },
        { role: "assistant", content: "Hey" },
      ],
    });

    expect(text).toBe("Hello world");

    const input = ConverseCommandMock.mock.calls[0]![0] as {
      modelId: string;
      system?: Array<{ text: string }>;
      messages: Array<{ role: string; content: Array<{ text: string }> }>;
      inferenceConfig: { maxTokens: number };
    };
    expect(input.modelId).toBe("eu.anthropic.claude-sonnet-4-6");
    expect(input.system).toEqual([{ text: "You are Bogi." }]);
    expect(input.messages).toEqual([
      { role: "user", content: [{ text: "Hi" }] },
      { role: "assistant", content: [{ text: "Hey" }] },
    ]);
    expect(input.inferenceConfig.maxTokens).toBe(128);
  });
});
