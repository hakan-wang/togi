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

// Frames yielded by a streaming transport (WebSocket). Mirrors the backend wsHandler frames.
export type StreamFrame =
  | { type: "delta"; text: string }
  | { type: "tool_use_start"; id: string; name: string }
  | { type: "tool_use_delta"; input: unknown }
  | { type: "stop"; stopReason?: string }
  | { type: "done" }
  | { type: "error"; message: string };

export type StreamFn = (body: InferRequest) => AsyncIterable<StreamFrame>;

export interface BogiProxyChatModelFields extends BaseChatModelParams {
  // Non-streaming HTTP fallback. Optional when a streaming `stream` transport is provided.
  post?: (body: InferRequest) => Promise<InferResponse>;
  // Streaming transport (WebSocket). When provided, _generate consumes it and emits onToken.
  stream?: StreamFn;
  onToken?: (delta: string) => void;
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
  private post?: BogiProxyChatModelFields["post"];
  // Named `streamFn` (not `stream`) to avoid colliding with the public `Runnable.stream` method.
  private streamFn?: StreamFn;
  private onToken?: (delta: string) => void;
  private system?: string;
  private maxTokens: number;
  private boundTools: InferRequest["tools"] = [];

  // Set by the dispatcher before each agent.invoke so emitted token frames can be
  // tagged with the id of the in-flight chat/plan/judge request. Read by the
  // injected `onToken` callback (wired in main.ts).
  activeRequestId: string | null = null;

  constructor(fields: BogiProxyChatModelFields) {
    super(fields);
    this.post = fields.post;
    this.streamFn = fields.stream;
    this.onToken = fields.onToken;
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
    const body: InferRequest = {
      system: this.system,
      messages: toInferMessages(messages),
      tools: this.boundTools?.length ? this.boundTools : undefined,
      maxTokens: this.maxTokens,
    };
    if (this.streamFn) {
      try {
        return await this.generateStreaming(body);
      } catch (err) {
        // Streaming failed (e.g. WS auth/connect error). If a non-streaming HTTP transport is
        // available, degrade to it so the agent still answers (just without token-by-token).
        if (!this.post) throw err;
      }
    }
    if (!this.post) throw new Error("BogiProxyChatModel requires either `post` or `stream`");
    const res = await this.post(body);
    const text = res.content.filter((b) => b.type === "text").map((b) => (b as any).text).join("");
    const toolCalls = res.content
      .filter((b) => b.type === "tool_use")
      .map((b) => ({ id: (b as any).id, name: (b as any).name, args: (b as any).input, type: "tool_call" as const }));
    const message = new AIMessage({ content: text, tool_calls: toolCalls });
    return { generations: [{ text, message }] };
  }

  private async generateStreaming(body: InferRequest): Promise<ChatResult> {
    let text = "";
    const toolCalls: { id: string; name: string; args: Record<string, any>; type: "tool_call" }[] = [];
    let current: { id: string; name: string; input: string } | null = null;
    const flushTool = () => {
      if (!current) return;
      let args: Record<string, any> = {};
      if (current.input) { try { args = JSON.parse(current.input); } catch { args = {}; } }
      toolCalls.push({ id: current.id, name: current.name, args, type: "tool_call" });
      current = null;
    };
    for await (const frame of this.streamFn!(body)) {
      if (frame.type === "delta") {
        text += frame.text;
        this.onToken?.(frame.text);
      } else if (frame.type === "tool_use_start") {
        flushTool();
        current = { id: frame.id, name: frame.name, input: "" };
      } else if (frame.type === "tool_use_delta") {
        if (current) current.input += typeof frame.input === "string" ? frame.input : JSON.stringify(frame.input);
      } else if (frame.type === "error") {
        throw new Error(frame.message);
      } else if (frame.type === "stop" || frame.type === "done") {
        break;
      }
    }
    flushTool();
    const message = new AIMessage({ content: text, tool_calls: toolCalls });
    return { generations: [{ text, message }] };
  }
}
