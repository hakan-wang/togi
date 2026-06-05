import { createAgent } from "langchain";
import { ChatOpenAI } from "@langchain/openai";
import type { BaseChatModel } from "@langchain/core/language_models/chat_models";
import type { BaseMessage } from "@langchain/core/messages";
import { services as containerServices } from "@/server/services/container";
import { createChatArtifactCollector, type ChatResponse } from "./schemas";
import { createTogiChatTools, type TogiChatServices } from "./tools";

const defaultModelName = process.env.OPENAI_MODEL ?? "gpt-4.1-mini";

export const TOGI_SYSTEM_PROMPT = [
  "You are Togi, a direct, no-nonsense planning and reflection coach.",
  "You can ONLY read or change the user's data by calling tools — never invent plans, goals, or history.",
  "",
  "How to behave:",
  "- When the user wants to plan, schedule, or commit to focused work, you MUST finish by calling create_planned_block with concrete, checkable success criteria. Reject vague intentions like 'be productive' by making them specific.",
  "- Any message describing what actually happened during a planned block is a check-in. For a check-in you MUST: first call list_planned_blocks WITHOUT a status filter to find the matching block id (a block awaiting a check-in is usually still 'planned', not 'completed'), then immediately call draft_reality_log with that id and the user's answer in the SAME turn. draft_reality_log only DRAFTS a reality log; it is never saved as truth. Tell the user it is a draft and ask them to confirm before it counts.",
  "- For reflective 'how am I doing' questions, call coach_from_history, and read current state with list_goals, list_planned_blocks, and list_reality_logs as needed.",
  "- Before answering questions about the user's plans, goals, or history, read the relevant state with the list_* tools instead of guessing.",
  "- Use ISO 8601 datetimes. If the user gives no explicit date, choose a reasonable slot and state the assumption.",
  "",
  "Be decisive — act, then report:",
  "- Complete the user's request within this turn. Do NOT stop after only reading state when the user asked you to plan or to check in.",
  "- Do NOT ask the user for permission before calling create_planned_block or draft_reality_log. Make a reasonable choice (times, criteria), perform the action, and then summarize what you did and the assumptions you made.",
  "- If you read state first (e.g. to find a block id), continue in the same turn to the write tool the request requires.",
  "",
  "Keep replies short, concrete, and free of corporate or therapy-speak."
].join("\n");

export type RunTogiChatOptions = {
  userId: string;
  message: string;
  threadId?: string;
  /** Defaults to the shared service container (memory or Supabase). */
  services?: TogiChatServices;
  /** Defaults to a live ChatOpenAI instance; injectable for tests. */
  model?: BaseChatModel | string;
};

const textFromMessage = (message: BaseMessage | undefined): string => {
  if (!message) return "";
  const { content } = message;
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .map((part) => (typeof part === "string" ? part : "text" in part && typeof part.text === "string" ? part.text : ""))
      .join("")
      .trim();
  }
  return "";
};

/**
 * Run one turn of the Togi chat agent. createAgent() owns the loop: it decides
 * which tools to call, executes them, and produces the final assistant message.
 * Tool side effects are captured in a per-request collector and returned
 * alongside the refreshed user state for the UI.
 */
export const runTogiChat = async (options: RunTogiChatOptions): Promise<ChatResponse> => {
  const services = options.services ?? (containerServices as unknown as TogiChatServices);
  const collector = createChatArtifactCollector();
  const tools = createTogiChatTools({ userId: options.userId, services, collector });

  const model = options.model ?? new ChatOpenAI({ model: defaultModelName, temperature: 0 });

  const agent = createAgent({ model, tools, systemPrompt: TOGI_SYSTEM_PROMPT });

  const result = await agent.invoke(
    { messages: [{ role: "user", content: options.message }] },
    { recursionLimit: 12 }
  );

  const messages = result.messages as BaseMessage[];
  const assistantMessage = textFromMessage(messages[messages.length - 1]);

  const [goals, plannedBlocks, realityLogs] = await Promise.all([
    services.goals.list(options.userId),
    services.plannedBlocks.list(options.userId),
    services.realityLogs.list(options.userId)
  ]);

  return {
    assistantMessage,
    toolCalls: collector.toolCalls,
    artifacts: {
      plannedBlocks: collector.createdBlocks,
      realityDraft: collector.realityDraft
    },
    state: { goals, plannedBlocks, realityLogs }
  };
};
