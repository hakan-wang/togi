import test from "node:test";
import assert from "node:assert/strict";
import { buildInferResponse, authBypassEnabled, buildHealthz } from "../src/handler.mjs";

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
