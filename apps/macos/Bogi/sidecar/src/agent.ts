import { createReactAgent } from "@langchain/langgraph/prebuilt";
import { MemorySaver } from "@langchain/langgraph";
import { type StructuredToolInterface } from "@langchain/core/tools";
import { BogiProxyChatModel, type BogiProxyChatModelFields } from "./proxyChatModel.js";
import { PERSONA } from "./persona.js";

export interface BogiAgentFields {
  tools: StructuredToolInterface[];
  post?: BogiProxyChatModelFields["post"];
  stream?: BogiProxyChatModelFields["stream"];
  onToken?: BogiProxyChatModelFields["onToken"];
}

export function createBogiAgent(fields: BogiAgentFields) {
  const model = new BogiProxyChatModel({
    post: fields.post,
    stream: fields.stream,
    onToken: fields.onToken,
    system: PERSONA,
  });
  // NOTE: the plan pins `createAgent` from `langchain` (the LangChain v1 API). The installed
  // `langchain@0.3.x` does not export `createAgent`; the equivalent prebuilt agent in this
  // version is `createReactAgent` from `@langchain/langgraph/prebuilt`. `systemPrompt` maps to
  // `prompt`, and `checkpointer` to `checkpointSaver`. The agent contract used by callers
  // (`invoke({ messages }) -> { messages }`) is identical.
  const agent = createReactAgent({
    llm: model,
    tools: fields.tools,
    prompt: PERSONA,
    checkpointSaver: new MemorySaver(),
  });

  // The MemorySaver checkpointer requires a `thread_id` in the invoke config. The real call
  // path (makeDispatcher / SidecarClient) always supplies one. We wrap `invoke` so callers
  // that do not pass a config (or pass one without a thread_id) still work, defaulting to a
  // single shared thread. This preserves the plan's `invoke({ messages }) -> { messages }`
  // contract while keeping cross-turn memory available when a thread_id is provided.
  const rawInvoke = agent.invoke.bind(agent);
  (agent as unknown as { invoke: (input: unknown, config?: any) => Promise<any> }).invoke = (
    input: unknown,
    config?: any
  ) => {
    const merged = {
      ...(config ?? {}),
      configurable: { thread_id: "default", ...(config?.configurable ?? {}) },
    };
    return rawInvoke(input as any, merged);
  };

  // Expose the underlying model so the dispatcher can tag streamed token frames with the
  // id of the in-flight request (set `model.activeRequestId` before each invoke).
  (agent as unknown as { __bogiModel: BogiProxyChatModel }).__bogiModel = model;

  return agent;
}
