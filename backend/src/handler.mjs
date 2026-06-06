import { BedrockRuntimeClient, ConverseCommand } from "@aws-sdk/client-bedrock-runtime";
import crypto from "node:crypto";
import { buildConverseInput, parseConverseOutput } from "./converse.mjs";

// Bogi backend — stateless proxy. Holds the Bedrock-invoking IAM role + (later) Supabase
// service key + Stripe secret. Stores NO user data; the memory bank stays on the Mac.
const REGION = process.env.BEDROCK_REGION || "eu-west-1";
const MODEL_ID = process.env.BEDROCK_MODEL_ID || "eu.anthropic.claude-sonnet-4-6";
const SUPABASE_URL = process.env.SUPABASE_URL || "";
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || "";
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY || "";
const STRIPE_WEBHOOK_SECRET = process.env.STRIPE_WEBHOOK_SECRET || "";
const AUTH_DISABLED = process.env.AUTH_DISABLED === "1";

const bedrock = new BedrockRuntimeClient({ region: REGION });

export const handler = async (event) => {
  const method = event?.requestContext?.http?.method || "GET";
  const path = event?.rawPath || "/";
  try {
    if (method === "GET" && path === "/healthz") return await healthz();
    if (method === "POST" && path === "/v1/infer") return await infer(event);
    if (method === "GET" && path === "/v1/account/status") return await accountStatus(event);
    if (method === "POST" && path === "/v1/stripe/webhook") return await stripeWebhook(event);
    return json(404, { error: "not_found" });
  } catch (err) {
    console.error("handler error", err);
    return json(500, { error: "internal", message: String(err?.message || err) });
  }
};

// --- Bedrock ---

async function callBedrock({ system, messages, tools, maxTokens = 1024, temperature = 0 }) {
  const cmd = new ConverseCommand(
    buildConverseInput({ modelId: MODEL_ID, system, messages, tools, maxTokens, temperature })
  );
  const res = await bedrock.send(cmd);
  return parseConverseOutput(res);
}

// Shape the /v1/infer JSON body. Exported for tests.
export function buildInferResponse(parsed) {
  return { text: parsed.text, content: parsed.content, stopReason: parsed.stopReason, usage: parsed.usage };
}

async function healthz() {
  const { text } = await callBedrock({
    messages: [{ role: "user", content: "Reply with exactly: bogi-bedrock-ok" }],
    maxTokens: 20,
  });
  return json(200, { ok: true, model: MODEL_ID, region: REGION, bedrock: text.trim() });
}

// --- /v1/infer (auth + paid gated) ---

async function infer(event) {
  const gate = await requirePaidUser(event);
  if (gate.error) return gate.error;

  const body = parseBody(event);
  if (!body?.messages?.length) return json(400, { error: "messages_required" });
  const parsed = await callBedrock({
    system: body.system,
    messages: body.messages,
    tools: body.tools,
    maxTokens: Math.min(body.maxTokens || 1024, 8192),
    temperature: body.temperature ?? 0,
  });
  return json(200, buildInferResponse(parsed));
}

// --- /v1/account/status ---

async function accountStatus(event) {
  const user = await authUser(event);
  if (!user) return json(401, { error: "unauthorized" });
  const { paid, plan } = await fetchPaid(user.id);
  return json(200, { paid, plan, userId: user.id });
}

// --- /v1/stripe/webhook (Stripe-gated; wired once STRIPE_WEBHOOK_SECRET is set) ---

async function stripeWebhook(event) {
  if (!STRIPE_WEBHOOK_SECRET) return json(503, { error: "stripe_not_configured" });
  const raw = rawBody(event);
  const sig = event.headers?.["stripe-signature"] || event.headers?.["Stripe-Signature"];
  if (!verifyStripeSignature(raw, sig, STRIPE_WEBHOOK_SECRET)) {
    return json(400, { error: "bad_signature" });
  }
  const evt = JSON.parse(raw);
  const userId =
    evt?.data?.object?.client_reference_id ||
    evt?.data?.object?.metadata?.supabase_user_id;
  if (userId) {
    const paid = ["checkout.session.completed", "customer.subscription.created",
      "customer.subscription.updated", "invoice.paid"].includes(evt.type);
    const canceled = evt.type === "customer.subscription.deleted";
    if (paid) await setPaid(userId, true, evt?.data?.object?.plan?.nickname || "paid");
    if (canceled) await setPaid(userId, false, null);
  }
  return json(200, { received: true });
}

// --- Supabase helpers ---

async function authUser(event) {
  if (AUTH_DISABLED) return { id: "dev-user" };
  if (!SUPABASE_URL) return null;
  // CloudFront OAC owns the `Authorization` header (SigV4), so the app sends the Supabase
  // access token in `X-Bogi-Authorization`. Fall back to Authorization for direct/dev calls.
  const h = event.headers || {};
  const auth = h["x-bogi-authorization"] || h["X-Bogi-Authorization"] || h.authorization || h.Authorization;
  const token = auth?.startsWith("Bearer ") ? auth.slice(7) : null;
  if (!token) return null;
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${token}`, apikey: SUPABASE_ANON_KEY },
  });
  if (!res.ok) return null;
  return await res.json();
}

async function fetchPaid(userId) {
  if (AUTH_DISABLED) return { paid: true, plan: "dev" };
  if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) return { paid: false, plan: null };
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/profiles?id=eq.${userId}&select=paid,plan`,
    { headers: { apikey: SUPABASE_SERVICE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_KEY}` } }
  );
  if (!res.ok) return { paid: false, plan: null };
  const rows = await res.json();
  return { paid: !!rows?.[0]?.paid, plan: rows?.[0]?.plan ?? null };
}

async function setPaid(userId, paid, plan) {
  if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) return;
  await fetch(`${SUPABASE_URL}/rest/v1/profiles?id=eq.${userId}`, {
    method: "PATCH",
    headers: {
      apikey: SUPABASE_SERVICE_KEY,
      Authorization: `Bearer ${SUPABASE_SERVICE_KEY}`,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    body: JSON.stringify({ paid, plan }),
  });
}

async function requirePaidUser(event) {
  const user = await authUser(event);
  if (!user) return { error: json(401, { error: "unauthorized" }) };
  const { paid } = await fetchPaid(user.id);
  if (!paid) return { error: json(402, { error: "payment_required" }) };
  return { user };
}

// --- Stripe signature (no SDK; HMAC over `${t}.${payload}`) ---

function verifyStripeSignature(payload, header, secret) {
  if (!header) return false;
  const parts = Object.fromEntries(header.split(",").map((p) => p.split("=")));
  const expected = crypto.createHmac("sha256", secret).update(`${parts.t}.${payload}`).digest("hex");
  try {
    return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(parts.v1 || ""));
  } catch {
    return false;
  }
}

// --- HTTP helpers ---

function parseBody(event) {
  try {
    return JSON.parse(rawBody(event));
  } catch {
    return null;
  }
}
function rawBody(event) {
  const b = event.body || "";
  return event.isBase64Encoded ? Buffer.from(b, "base64").toString("utf8") : b;
}
function json(statusCode, obj) {
  return { statusCode, headers: { "content-type": "application/json" }, body: JSON.stringify(obj) };
}
