import { BedrockRuntimeClient, ConverseCommand } from "@aws-sdk/client-bedrock-runtime";
import crypto from "node:crypto";
import { buildConverseInput, parseConverseOutput } from "./converse.mjs";

// Togi backend — stateless proxy. Holds the Bedrock-invoking IAM role + Supabase service
// key + Stripe secret. Stores no user data beyond the auth/paid profile and a per-day AI
// usage counter; the memory bank stays on the Mac.
const REGION = process.env.BEDROCK_REGION || "eu-west-1";
const MODEL_ID = process.env.BEDROCK_MODEL_ID || "eu.anthropic.claude-sonnet-4-6";
const SUPABASE_URL = process.env.SUPABASE_URL || "";
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || "";
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY || "";
const STRIPE_SECRET_KEY = process.env.STRIPE_SECRET_KEY || "";
const STRIPE_WEBHOOK_SECRET = process.env.STRIPE_WEBHOOK_SECRET || "";
const STRIPE_PRICE_ID = process.env.STRIPE_PRICE_ID || "";
const CHECKOUT_SUCCESS_URL = process.env.CHECKOUT_SUCCESS_URL || "https://heytogi.com/upgrade-success";
const CHECKOUT_CANCEL_URL = process.env.CHECKOUT_CANCEL_URL || "https://heytogi.com/upgrade-cancelled";
const BILLING_RETURN_URL = process.env.BILLING_RETURN_URL || "https://heytogi.com";
// The auth bypass is honored ONLY in genuine local dev — i.e. when no Supabase project is
// configured. If AUTH_DISABLED=1 ever slips into a real deploy (SUPABASE_URL set), we ignore
// it and keep auth ENFORCED, so a single stray env var can't make the paid endpoint public.
// Exported pure for tests.
export function authBypassEnabled(env) {
  return env.AUTH_DISABLED === "1" && !env.SUPABASE_URL;
}
const AUTH_DISABLED = authBypassEnabled(process.env);
if (process.env.AUTH_DISABLED === "1" && process.env.SUPABASE_URL) {
  console.error(
    "AUTH_DISABLED=1 ignored: SUPABASE_URL is set (treated as a real deploy); auth stays ENFORCED."
  );
}

const bedrock = new BedrockRuntimeClient({ region: REGION });

export const handler = async (event) => {
  const method = event?.requestContext?.http?.method || "GET";
  const path = event?.rawPath || "/";
  try {
    if (method === "GET" && path === "/healthz") return await healthz(event);
    if (method === "POST" && path === "/v1/infer") return await infer(event);
    if (method === "GET" && path === "/v1/account/status") return await accountStatus(event);
    if (method === "POST" && path === "/v1/stripe/checkout") return await stripeCheckout(event);
    if (method === "POST" && path === "/v1/stripe/portal") return await stripePortal(event);
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

// Build the form-encoded body for a single-price subscription Checkout Session. Pure +
// exported for tests. client_reference_id + subscription metadata let the webhook map
// Stripe -> Supabase user.
export function buildCheckoutForm({ userId, email, stripeCustomerId, priceId, successUrl, cancelUrl }) {
  const form = {
    mode: "subscription",
    "line_items[0][price]": priceId,
    "line_items[0][quantity]": "1",
    client_reference_id: userId,
    "subscription_data[metadata][supabase_user_id]": userId,
    "metadata[supabase_user_id]": userId,
    allow_promotion_codes: "true",
    success_url: `${successUrl}?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: cancelUrl,
  };
  if (stripeCustomerId) form.customer = stripeCustomerId;
  else if (email) form.customer_email = email;
  return form;
}

// Shape the slimmed /v1/account/status body. Pure + exported for tests.
export function buildAccountStatus({ paid, plan, userId }) {
  return { paid, plan, userId };
}

// Paid-only access decision. Pure + exported for tests.
export function subscriptionGate(paid) {
  if (!paid) return { allow: false, status: 403, body: { error: "subscription_required" } };
  return { allow: true };
}

// Static liveness body. authDisabled is surfaced so a wide-open (dev) deploy is obvious
// from a health check. Exported pure for tests.
export function buildHealthz({ authDisabled }) {
  return { ok: true, model: MODEL_ID, region: REGION, authDisabled };
}

// True when the caller asked for the deep (Bedrock-pinging) probe via ?deep=1.
function wantsDeepProbe(event) {
  if (event?.queryStringParameters?.deep === "1") return true;
  return (event?.rawQueryString || "").split("&").includes("deep=1");
}

async function healthz(event) {
  const base = buildHealthz({ authDisabled: AUTH_DISABLED });
  // The Bedrock connectivity ping costs money, so it is NOT run for the default health
  // check — that path is public (Function URL auth NONE) and would otherwise let anyone
  // run up the Bedrock bill. Opt into it with ?deep=1, and only when authenticated.
  if (!wantsDeepProbe(event)) return json(200, base);
  const user = await authUser(event);
  if (!user) return json(401, { error: "unauthorized" });
  const { text } = await callBedrock({
    messages: [{ role: "user", content: "Reply with exactly: bogi-bedrock-ok" }],
    maxTokens: 20,
  });
  return json(200, { ...base, bedrock: text.trim() });
}

// --- /v1/infer (auth + subscription gated) ---

async function infer(event) {
  const user = await authUser(event);
  if (!user) return json(401, { error: "unauthorized" });

  const { paid } = await fetchProfile(user.id);
  const gate = subscriptionGate(paid);
  if (!gate.allow) return json(gate.status, gate.body);

  const body = parseBody(event);
  if (!body?.messages?.length) return json(400, { error: "messages_required" });
  const parsed = await callBedrock({
    system: body.system,
    messages: body.messages,
    tools: body.tools,
    maxTokens: Math.min(body.maxTokens || 1024, 8192),
    temperature: body.temperature ?? 0,
  });
  return json(200, { ...buildInferResponse(parsed), paid });
}

// --- /v1/account/status ---

async function accountStatus(event) {
  const user = await authUser(event);
  if (!user) return json(401, { error: "unauthorized" });
  const { paid, plan } = await fetchProfile(user.id);
  return json(200, buildAccountStatus({ paid, plan, userId: user.id }));
}

// --- /v1/stripe/checkout (auth required; opens a subscription Checkout) ---

async function stripeCheckout(event) {
  if (!STRIPE_SECRET_KEY || !STRIPE_PRICE_ID) return json(503, { error: "stripe_not_configured" });
  const user = await authUser(event);
  if (!user) return json(401, { error: "unauthorized" });

  const { stripeCustomerId } = await fetchProfile(user.id);
  const form = buildCheckoutForm({
    userId: user.id,
    email: user.email,
    stripeCustomerId,
    priceId: STRIPE_PRICE_ID,
    successUrl: CHECKOUT_SUCCESS_URL,
    cancelUrl: CHECKOUT_CANCEL_URL,
  });

  const res = await stripePost("/v1/checkout/sessions", form);
  if (!res.ok || !res.json?.url) {
    console.error("stripe checkout error", res.status, res.body);
    return json(502, { error: "stripe_error" });
  }
  return json(200, { url: res.json.url });
}

// --- /v1/stripe/portal (auth required; manage/cancel an existing subscription) ---

async function stripePortal(event) {
  if (!STRIPE_SECRET_KEY) return json(503, { error: "stripe_not_configured" });
  const user = await authUser(event);
  if (!user) return json(401, { error: "unauthorized" });

  const { stripeCustomerId } = await fetchProfile(user.id);
  if (!stripeCustomerId) return json(409, { error: "no_subscription" });

  const res = await stripePost("/v1/billing_portal/sessions", {
    customer: stripeCustomerId,
    return_url: BILLING_RETURN_URL,
  });
  if (!res.ok || !res.json?.url) {
    console.error("stripe portal error", res.status, res.body);
    return json(502, { error: "stripe_error" });
  }
  return json(200, { url: res.json.url });
}

// --- /v1/stripe/webhook (Stripe-gated; flips profiles.paid + stores customer id) ---

async function stripeWebhook(event) {
  if (!STRIPE_WEBHOOK_SECRET) return json(503, { error: "stripe_not_configured" });
  const raw = rawBody(event);
  const sig = event.headers?.["stripe-signature"] || event.headers?.["Stripe-Signature"];
  if (!verifyStripeSignature(raw, sig, STRIPE_WEBHOOK_SECRET)) {
    return json(400, { error: "bad_signature" });
  }

  const evt = JSON.parse(raw);
  const type = evt?.type || "";
  const obj = evt?.data?.object || {};

  // Decide paid/unpaid. Subscription events carry an authoritative status; other events
  // are mapped by type.
  let paid;
  if (type.startsWith("customer.subscription.")) {
    paid = ["active", "trialing", "past_due"].includes(obj.status);
  } else if (["checkout.session.completed", "invoice.paid", "invoice.payment_succeeded"].includes(type)) {
    paid = true;
  } else {
    return json(200, { ignored: type });
  }

  // Validate identifiers before they ever touch a query filter. The metadata user id is
  // attacker-influenceable in principle (Payment Links, dashboard sessions), so it is only
  // trusted to BIND a brand-new profile, never to hijack one already tied to another customer.
  const customerId = isStripeCustomer(obj.customer) ? obj.customer : null;
  const metaUser =
    obj.client_reference_id ||
    obj.metadata?.supabase_user_id ||
    obj.subscription_details?.metadata?.supabase_user_id ||
    null;
  const userId = isUuid(metaUser) ? metaUser : null;

  const fields = { paid, plan: paid ? planFromPrice(obj) : null };
  if (customerId) fields.stripe_customer_id = customerId;

  // Resolve the target profile. Prefer the customer id (our durable join key) once bound.
  let target = null;
  if (customerId) {
    const existing = await findProfileByCustomer(customerId);
    if (existing) target = { filter: `stripe_customer_id=eq.${encodeURIComponent(customerId)}` };
  }
  if (!target && userId) {
    const prof = await fetchProfile(userId);
    if (prof.stripeCustomerId && customerId && prof.stripeCustomerId !== customerId) {
      console.warn("webhook customer mismatch for user", userId);
      return json(200, { ignored: "customer_mismatch" });
    }
    target = { upsertId: userId };
  }
  if (!target) return json(200, { ignored: "unresolved" });

  // Ask Stripe to retry (5xx) if the write matched no row / failed, rather than losing a
  // paid user silently (PostgREST PATCH returns 200 even when zero rows match).
  const wrote = await writeProfile(target, fields);
  if (!wrote) return json(500, { error: "profile_write_failed" });
  return json(200, { received: true });
}

// --- Supabase helpers ---

function svcHeaders() {
  return { apikey: SUPABASE_SERVICE_KEY, Authorization: `Bearer ${SUPABASE_SERVICE_KEY}` };
}

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

async function fetchProfile(userId) {
  if (AUTH_DISABLED) return { paid: true, plan: "dev", stripeCustomerId: null };
  if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) return { paid: false, plan: null, stripeCustomerId: null };
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}&select=paid,plan,stripe_customer_id`,
    { headers: svcHeaders() }
  );
  if (!res.ok) return { paid: false, plan: null, stripeCustomerId: null };
  const rows = await res.json();
  const r = rows?.[0];
  return { paid: !!r?.paid, plan: r?.plan ?? null, stripeCustomerId: r?.stripe_customer_id ?? null };
}

async function findProfileByCustomer(customerId) {
  if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) return null;
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/profiles?stripe_customer_id=eq.${encodeURIComponent(customerId)}&select=id`,
    { headers: svcHeaders() }
  );
  if (!res.ok) return null;
  const rows = await res.json();
  return rows?.[0] ?? null;
}

// Write the profile and report whether a row was actually affected. `upsertId` creates the
// row if the signup trigger lagged; `filter` patches an already-bound profile. Returns false
// on a failed/zero-row write so the webhook can 5xx and let Stripe retry instead of dropping it.
async function writeProfile(target, fields) {
  if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) return false;
  let res;
  if (target.upsertId) {
    res = await fetch(`${SUPABASE_URL}/rest/v1/profiles`, {
      method: "POST",
      headers: {
        ...svcHeaders(),
        "Content-Type": "application/json",
        Prefer: "resolution=merge-duplicates,return=representation",
      },
      body: JSON.stringify({ id: target.upsertId, ...fields }),
    });
  } else {
    res = await fetch(`${SUPABASE_URL}/rest/v1/profiles?${target.filter}`, {
      method: "PATCH",
      headers: { ...svcHeaders(), "Content-Type": "application/json", Prefer: "return=representation" },
      body: JSON.stringify(fields),
    });
  }
  if (!res.ok) {
    console.error("writeProfile failed", res.status);
    return false;
  }
  const rows = await res.json().catch(() => []);
  return Array.isArray(rows) ? rows.length > 0 : true;
}

// Single plan today; the canonical plan name is always "pro".
function planFromPrice() {
  return "pro";
}

// --- Stripe REST (no SDK; form-encoded like the Stripe API expects) ---

async function stripePost(path, form) {
  const res = await fetch(`https://api.stripe.com${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams(form).toString(),
  });
  const text = await res.text();
  let parsed = null;
  try {
    parsed = JSON.parse(text);
  } catch {
    /* non-JSON error body */
  }
  return { ok: res.ok, status: res.status, body: text, json: parsed };
}

// --- Stripe signature (no SDK; HMAC over `${t}.${payload}`) ---

function verifyStripeSignature(payload, header, secret, toleranceSec = 300) {
  if (!header) return false;
  const parts = Object.fromEntries(header.split(",").map((p) => p.split("=")));
  // Reject stale/replayed events: the signed timestamp must be within the tolerance window.
  const ts = Number(parts.t);
  if (!Number.isFinite(ts) || Math.abs(Date.now() / 1000 - ts) > toleranceSec) return false;
  const expected = crypto.createHmac("sha256", secret).update(`${parts.t}.${payload}`).digest("hex");
  try {
    return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(parts.v1 || ""));
  } catch {
    return false;
  }
}

// --- helpers ---

// Strict id shape checks so attacker-influenceable webhook fields can never reshape a query.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function isUuid(s) {
  return typeof s === "string" && UUID_RE.test(s);
}
function isStripeCustomer(s) {
  return typeof s === "string" && /^cus_[A-Za-z0-9]+$/.test(s);
}

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
