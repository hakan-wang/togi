/**
 * POST /v1/infer
 *
 * verify Supabase JWT → check paid status → forward to Bedrock Converse → { text }.
 * Stateless: nothing about the request or response content is logged or stored.
 */
import type { APIGatewayProxyEventV2 } from "aws-lambda";
import { authenticate } from "../lib/auth.js";
import { converse, type ChatMessage, type Role } from "../lib/bedrock.js";
import { config } from "../lib/config.js";
import { BadRequestError, json, parseJsonBody, PaymentRequiredError, type HttpResponse } from "../lib/http.js";
import { getProfile } from "../lib/supabase.js";

interface InferBody {
  model?: string;
  messages?: Array<{ role?: string; content?: string }>;
  max_tokens?: number;
}

const VALID_ROLES: ReadonlySet<string> = new Set<Role>(["system", "user", "assistant"]);

function parseMessages(raw: InferBody["messages"]): ChatMessage[] {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new BadRequestError("`messages` must be a non-empty array");
  }
  return raw.map((m, i) => {
    if (!m || typeof m.role !== "string" || !VALID_ROLES.has(m.role)) {
      throw new BadRequestError(`messages[${i}].role must be one of system|user|assistant`);
    }
    if (typeof m.content !== "string") {
      throw new BadRequestError(`messages[${i}].content must be a string`);
    }
    return { role: m.role as Role, content: m.content };
  });
}

export async function handleInfer(event: APIGatewayProxyEventV2): Promise<HttpResponse> {
  const user = await authenticate(event.headers);

  const body = parseJsonBody<InferBody>(event.body);
  const messages = parseMessages(body.messages);
  const maxTokens =
    typeof body.max_tokens === "number" && body.max_tokens > 0 ? Math.floor(body.max_tokens) : 1024;
  const modelId = typeof body.model === "string" && body.model ? body.model : config.bedrockModelId;

  if (!config.authDisabled) {
    const profile = await getProfile(user.id);
    if (!profile.paid) {
      throw new PaymentRequiredError("Active subscription required");
    }
  }

  const text = await converse({ modelId, messages, maxTokens });
  return json(200, { text });
}
