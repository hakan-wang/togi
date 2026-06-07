import test from "node:test";
import assert from "node:assert/strict";
import { buildInferResponse, authBypassEnabled, buildHealthz, buildCheckoutForm, buildAccountStatus } from "../src/handler.mjs";

test("buildCheckoutForm builds a single-price subscription form with user binding", () => {
  const form = buildCheckoutForm({
    userId: "11111111-1111-1111-1111-111111111111",
    email: "a@b.com",
    stripeCustomerId: null,
    priceId: "price_123",
    successUrl: "https://heytogi.com/ok",
    cancelUrl: "https://heytogi.com/no",
  });
  assert.equal(form.mode, "subscription");
  assert.equal(form["line_items[0][price]"], "price_123");
  assert.equal(form["line_items[0][quantity]"], "1");
  assert.equal(form.client_reference_id, "11111111-1111-1111-1111-111111111111");
  assert.equal(form["subscription_data[metadata][supabase_user_id]"], "11111111-1111-1111-1111-111111111111");
  assert.equal(form.customer_email, "a@b.com");
  assert.equal(form.success_url, "https://heytogi.com/ok?session_id={CHECKOUT_SESSION_ID}");
  assert.equal(form["line_items[1][price]"], undefined); // single price only
});

test("buildCheckoutForm prefers an existing stripe customer over email", () => {
  const form = buildCheckoutForm({
    userId: "11111111-1111-1111-1111-111111111111",
    email: "a@b.com",
    stripeCustomerId: "cus_abc",
    priceId: "price_123",
    successUrl: "https://x/ok",
    cancelUrl: "https://x/no",
  });
  assert.equal(form.customer, "cus_abc");
  assert.equal(form.customer_email, undefined);
});

test("buildAccountStatus returns paid, plan, userId only", () => {
  const body = buildAccountStatus({ paid: true, plan: "pro", userId: "u1" });
  assert.deepEqual(body, { paid: true, plan: "pro", userId: "u1" });
});

test("buildInferResponse returns text, content, stopReason for tool calls", () => {
  const parsed = {
    text: "looking",
    content: [{ type: "tool_use", id: "t1", name: "search_activity", input: { q: "x" } }],
    stopReason: "tool_use",
    usage: { outputTokens: 3 },
  };
  const body = buildInferResponse(parsed);
  assert.equal(body.text, "looking");
  assert.equal(body.stopReason, "tool_use");
  assert.equal(body.content[0].type, "tool_use");
  assert.deepEqual(body.usage, { outputTokens: 3 });
});

test("authBypassEnabled only honors AUTH_DISABLED in true local dev (no SUPABASE_URL)", () => {
  // Real/prod deploy: SUPABASE_URL set → bypass is IGNORED even with AUTH_DISABLED=1.
  assert.equal(authBypassEnabled({ AUTH_DISABLED: "1", SUPABASE_URL: "https://x.supabase.co" }), false);
  // Pure local dev: no Supabase configured → bypass allowed.
  assert.equal(authBypassEnabled({ AUTH_DISABLED: "1", SUPABASE_URL: "" }), true);
  assert.equal(authBypassEnabled({ AUTH_DISABLED: "1" }), true);
  // Bypass off by default.
  assert.equal(authBypassEnabled({ SUPABASE_URL: "" }), false);
});

test("buildHealthz is a static body with no Bedrock fields", () => {
  const body = buildHealthz({ authDisabled: false });
  assert.equal(body.ok, true);
  assert.equal(body.authDisabled, false);
  assert.equal("bedrock" in body, false); // default health check must not ping Bedrock
});
