import { BedrockRuntimeClient, ConverseStreamCommand } from "@aws-sdk/client-bedrock-runtime";
import { ApiGatewayManagementApiClient, PostToConnectionCommand } from "@aws-sdk/client-apigatewaymanagementapi";
import { buildConverseInput } from "./converse.mjs";

const REGION = process.env.BEDROCK_REGION || "eu-west-1";
const MODEL_ID = process.env.BEDROCK_MODEL_ID || "eu.anthropic.claude-sonnet-4-6";
const bedrock = new BedrockRuntimeClient({ region: REGION });

// Pure: map one Bedrock ConverseStream event to a client frame (or null to skip).
export function streamEventToFrame(ev) {
  if (ev.contentBlockDelta?.delta?.text != null) return { type: "delta", text: ev.contentBlockDelta.delta.text };
  if (ev.contentBlockDelta?.delta?.toolUse?.input != null) return { type: "tool_use_delta", input: ev.contentBlockDelta.delta.toolUse.input };
  const tu = ev.contentBlockStart?.start?.toolUse;
  if (tu) return { type: "tool_use_start", id: tu.toolUseId, name: tu.name };
  if (ev.messageStop) return { type: "stop", stopReason: ev.messageStop.stopReason };
  return null;
}

export const handler = async (event) => {
  const route = event?.requestContext?.routeKey;
  if (route === "$connect") return await onConnect(event);
  if (route === "$disconnect") return { statusCode: 200 };
  if (route === "infer") return await onInfer(event);
  return { statusCode: 404 };
};

async function onConnect(event) {
  // Authorize at connect time; token in query string (set by the sidecar).
  const token = event?.queryStringParameters?.token;
  const ok = await authorize(token);
  return { statusCode: ok ? 200 : 401 };
}

async function onInfer(event) {
  const { domainName, stage, connectionId } = event.requestContext;
  const mgmt = new ApiGatewayManagementApiClient({ region: REGION, endpoint: `https://${domainName}/${stage}` });
  const send = (obj) => mgmt.send(new PostToConnectionCommand({ ConnectionId: connectionId, Data: Buffer.from(JSON.stringify(obj)) }));
  let body;
  try { body = JSON.parse(event.body || "{}"); } catch { await send({ type: "error", message: "bad_json" }); return { statusCode: 400 }; }
  try {
    const input = buildConverseInput({ modelId: MODEL_ID, system: body.system, messages: body.messages, tools: body.tools, maxTokens: Math.min(body.maxTokens || 1024, 8192) });
    const res = await bedrock.send(new ConverseStreamCommand(input));
    for await (const ev of res.stream || []) {
      const frame = streamEventToFrame(ev);
      if (frame) await send(frame);
    }
    await send({ type: "done" });
  } catch (err) {
    await send({ type: "error", message: String(err?.message || err) });
  }
  return { statusCode: 200 };
}

async function authorize(token) {
  if (process.env.AUTH_DISABLED === "1") return true;
  if (!token || !process.env.SUPABASE_URL) return false;
  const r = await fetch(`${process.env.SUPABASE_URL}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${token}`, apikey: process.env.SUPABASE_ANON_KEY || "" },
  });
  return r.ok;
}
