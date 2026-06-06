/**
 * Bedrock Converse wrapper. Maps the app's `{ role, content }` message shape to
 * the Converse API: `system` messages become top-level system blocks, while
 * user/assistant messages become conversation turns. Returns only the assistant
 * text — nothing about the content is logged or stored.
 */
import {
  BedrockRuntimeClient,
  ConverseCommand,
  type Message,
  type SystemContentBlock,
} from "@aws-sdk/client-bedrock-runtime";
import { config } from "./config.js";

let client: BedrockRuntimeClient | null = null;

function getClient(): BedrockRuntimeClient {
  if (!client) {
    client = new BedrockRuntimeClient({ region: config.bedrockRegion });
  }
  return client;
}

export type Role = "system" | "user" | "assistant";

export interface ChatMessage {
  role: Role;
  content: string;
}

export interface ConverseArgs {
  modelId: string;
  messages: ChatMessage[];
  maxTokens: number;
}

export async function converse(args: ConverseArgs): Promise<string> {
  const system: SystemContentBlock[] = [];
  const messages: Message[] = [];

  for (const message of args.messages) {
    if (message.role === "system") {
      system.push({ text: message.content });
    } else {
      messages.push({
        role: message.role,
        content: [{ text: message.content }],
      });
    }
  }

  const command = new ConverseCommand({
    modelId: args.modelId,
    system: system.length > 0 ? system : undefined,
    messages,
    inferenceConfig: { maxTokens: args.maxTokens },
  });

  const response = await getClient().send(command);
  const text =
    response.output?.message?.content
      ?.map((block) => block.text ?? "")
      .join("")
      .trim() ?? "";

  return text;
}
