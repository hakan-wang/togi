// Pure translation between Bogi's request/response shape and Bedrock Converse.
// No network here so it is unit-testable. Supports text-only (backward compatible)
// and tool use (toolConfig + tool_use / tool_result content blocks).

function toContentBlocks(content) {
  // String content -> a single text block (legacy path).
  if (typeof content === "string") return [{ text: content }];
  // Array of typed blocks -> Converse content blocks.
  return (content || []).map((b) => {
    if (b.type === "text") return { text: b.text };
    if (b.type === "tool_use") {
      return { toolUse: { toolUseId: b.id, name: b.name, input: b.input } };
    }
    if (b.type === "tool_result") {
      const inner = typeof b.content === "string" ? [{ text: b.content }] : b.content;
      return { toolResult: { toolUseId: b.tool_use_id, content: inner } };
    }
    return { text: String(b.text ?? "") };
  });
}

// Bedrock Converse requires strictly alternating user/assistant turns, and ALL toolResult
// blocks answering one assistant turn's tool_use ids must live in a SINGLE following user
// message. LangChain emits one ToolMessage per tool call (hence several consecutive user
// messages), so we merge adjacent same-role messages by concatenating their content blocks.
function coalesceByRole(mapped) {
  const out = [];
  for (const m of mapped) {
    const last = out[out.length - 1];
    if (last && last.role === m.role) last.content = last.content.concat(m.content);
    else out.push({ role: m.role, content: [...m.content] });
  }
  return out;
}

export function buildConverseInput({ modelId, system, messages, tools, maxTokens = 1024, temperature = 0 }) {
  const input = {
    modelId,
    system: system ? [{ text: system }] : undefined,
    messages: coalesceByRole((messages || []).map((m) => ({ role: m.role, content: toContentBlocks(m.content) }))),
    inferenceConfig: { maxTokens, temperature },
  };
  if (tools && tools.length) {
    input.toolConfig = {
      tools: tools.map((t) => ({
        toolSpec: {
          name: t.name,
          description: t.description,
          inputSchema: { json: t.input_schema },
        },
      })),
    };
  }
  return input;
}

export function parseConverseOutput(res) {
  const blocks = res.output?.message?.content || [];
  const content = blocks.map((b) => {
    if (b.text != null) return { type: "text", text: b.text };
    if (b.toolUse) {
      return { type: "tool_use", id: b.toolUse.toolUseId, name: b.toolUse.name, input: b.toolUse.input };
    }
    return { type: "text", text: "" };
  });
  const text = content.filter((c) => c.type === "text").map((c) => c.text).join("");
  return { text, content, stopReason: res.stopReason, usage: res.usage };
}
