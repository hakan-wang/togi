import test from "node:test";
import assert from "node:assert/strict";
import { buildInferResponse, buildCheckoutForm } from "../src/handler.mjs";

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
