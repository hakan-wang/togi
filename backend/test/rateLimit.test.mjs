import test from "node:test";
import assert from "node:assert/strict";
import { rateLimitStep } from "../src/handler.mjs";

const LIMITS = { perMin: 3, perDay: 5 };
const T0 = 1_000_000_000_000; // fixed base time (ms)

test("first request is allowed and starts both counters at 1", () => {
  const s = rateLimitStep(undefined, T0, LIMITS);
  assert.equal(s.allow, true);
  assert.equal(s.rec.minCount, 1);
  assert.equal(s.rec.dayCount, 1);
});

test("per-minute burst blocks once the minute cap is hit", () => {
  let rec;
  for (let i = 0; i < LIMITS.perMin; i++) {
    const s = rateLimitStep(rec, T0, LIMITS);
    assert.equal(s.allow, true, `request ${i + 1} should pass`);
    rec = s.rec;
  }
  const blocked = rateLimitStep(rec, T0, LIMITS);
  assert.equal(blocked.allow, false);
  assert.equal(blocked.scope, "minute");
  assert.ok(blocked.retryAfter > 0 && blocked.retryAfter <= 60);
});

test("a new minute resets the burst counter", () => {
  let rec;
  for (let i = 0; i < LIMITS.perMin; i++) rec = rateLimitStep(rec, T0, LIMITS).rec;
  // jump to the next minute window
  const s = rateLimitStep(rec, T0 + 60_000, LIMITS);
  assert.equal(s.allow, true);
  assert.equal(s.rec.minCount, 1);
});

test("the per-day cap blocks even across fresh minutes", () => {
  let rec;
  // Spend the daily budget one-per-minute so the burst cap never trips.
  for (let i = 0; i < LIMITS.perDay; i++) {
    const s = rateLimitStep(rec, T0 + i * 60_000, LIMITS);
    assert.equal(s.allow, true, `day request ${i + 1} should pass`);
    rec = s.rec;
  }
  const blocked = rateLimitStep(rec, T0 + LIMITS.perDay * 60_000, LIMITS);
  assert.equal(blocked.allow, false);
  assert.equal(blocked.scope, "day");
  assert.ok(blocked.retryAfter > 0 && blocked.retryAfter <= 86_400);
});

test("a new day resets the daily counter", () => {
  let rec;
  for (let i = 0; i < LIMITS.perDay; i++) rec = rateLimitStep(rec, T0 + i * 60_000, LIMITS).rec;
  const s = rateLimitStep(rec, T0 + 86_400_000, LIMITS);
  assert.equal(s.allow, true);
  assert.equal(s.rec.dayCount, 1);
});
