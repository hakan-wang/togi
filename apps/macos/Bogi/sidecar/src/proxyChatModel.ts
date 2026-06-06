import { BaseChatModel, type BaseChatModelParams } from "@langchain/core/language_models/chat_models";
import { AIMessage, type BaseMessage } from "@langchain/core/messages";
import { ChatResult } from "@langchain/core/outputs";
import { type StructuredToolInterface } from "@langchain/core/tools";
import { zodToJsonSchema } from "zod-to-json-schema";

type InferBlock =
  | { type: "text"; text: string }
  | { type: "tool_use"; id: string; name: string; input: unknown }
  | { type: "tool_result"; tool_use_id: string; content: string };

interface InferResponse { text: string; content: InferBlock[]; stopReason: string }
interface InferRequest {
  system?: string;
  messages: { role: string; content: string | InferBlock[] }[];
  tools?: { name: string; description: string; input_schema: unknown }[];
  maxTokens?: number;
}

export interface BogiProxyChatModelFields extends BaseChatModelParams {
  post: (body: InferRequest) => Promise<InferResponse>;
  system?: string;
  maxTokens?: number;
}

function toInferMessages(messages: BaseMessage[]): InferRequest["messages"] {
  return messages
    .filter((m) => m.getType() !== "system")
    .map((m) => {
    const role = m.getType() === "human" ? "user" : m.getType() === "ai" ? "assistant" : "user";
    if (m.getType() === "tool") {
      const tm = m as unknown as { tool_call_id: string; content: string };
      return { role: "user", content: [{ type: "tool_result", tool_use_id: tm.tool_call_id, content: String(tm.content) }] };
    }
    if (m.getType() === "ai") {
      const ai = m as AIMessage;
      if (ai.tool_calls?.length) {
        return {
          role: "assistant",
          content: ai.tool_calls.map((tc) => ({ type: "tool_use" as const, id: tc.id!, name: tc.name, input: tc.args })),
        };
      }
    }
    return { role, content: String(m.content) };
  });
}

export class BogiProxyChatModel extends BaseChatModel {
  private post: BogiProxyChatModelFields["post"];
  private system?: string;
  private maxTokens: number;
  private boundTools: InferRequest["tools"] = [];

  constructor(fields: BogiProxyChatModelFields) {
    super(fields);
    this.post = fields.post;
    this.system = fields.system;
    this.maxTokens = fields.maxTokens ?? 1024;
  }

  _llmType(): string { return "bogi-proxy"; }

  override bindTools(tools: StructuredToolInterface[]) {
    this.boundTools = tools.map((t) => ({
      name: t.name,
      description: t.description,
      input_schema: zodToJsonSchema(t.schema as any),
    }));
    return this;
  }

  async _generate(messages: BaseMessage[]): Promise<ChatResult> {
    const res = await this.post({
      system: this.system,
      messages: toInferMessages(messages),
      tools: this.boundTools?.length ? this.boundTools : undefined,
      maxTokens: this.maxTokens,
    });
    const text = res.content.filter((b) => b.type === "text").map((b) => (b as any).text).join("");
    const toolCalls = res.content
      .filter((b) => b.type === "tool_use")
      .map((b) => ({ id: (b as any).id, name: (b as any).name, args: (b as any).input, type: "tool_call" as const }));
    const message = new AIMessage({ content: text, tool_calls: toolCalls });
    return { generations: [{ text, message }] };
  }
}
