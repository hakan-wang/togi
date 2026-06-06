# Subscription Account Sync + Gated macOS Login — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Togi subscription-only — the AWS Lambda backend gates inference on an active Stripe subscription synced to Supabase, and the macOS app unlocks only for a signed-in, subscribed user.

**Architecture:** Supabase `profiles.paid` is the source of truth for access; Stripe pushes subscription changes to it via the backend webhook (already built). The backend switches `/v1/infer` from freemium to paid-only and collapses to a single Stripe price. The macOS app gains a launch gate (Login → Subscribe → Blocked → Unlocked) that runs a strict online check before starting capture/mascot/sidecar.

**Tech Stack:** Node.js (ESM, `node:test`) for the backend Lambda; Swift / SwiftUI / AppKit (SwiftPM, XCTest target `BogiAppTests`) for the macOS app.

**Spec:** `docs/superpowers/specs/2026-06-06-subscription-account-sync-design.md`

---

## File Structure

**Backend (`backend/`)**
- Modify `src/handler.mjs` — paid-only `/v1/infer`, single-price checkout, slimmer `/v1/account/status`; extract pure helpers `subscriptionGate`, `buildCheckoutForm`, `buildAccountStatus`.
- Modify `test/infer.test.mjs` — add tests for the new pure helpers.
- Delete `supabase/ai_usage.sql` — freemium-only, not deployed.
- Modify `deploy.sh` — single `STRIPE_PRICE_ID`, drop `STRIPE_PRICE_MONTHLY/ANNUAL` and `FREE_DAILY_LIMIT`.

**macOS app (`apps/macos/Bogi/`)**
- Create `Sources/BogiApp/Infrastructure/AI/WebsiteConfig.swift` — pricing/account URLs.
- Modify `Sources/BogiApp/Infrastructure/Auth/AccountGate.swift` — add `GateOutcome` + injectable `check()`.
- Create `Sources/BogiApp/Infrastructure/Auth/GateState.swift` — pure outcome→state reducer.
- Modify `Sources/BogiApp/Infrastructure/AI/InferenceClient.swift` — map 403 → `.subscriptionRequired`.
- Modify `Sources/BogiApp/UI/PaywallView.swift` — single-plan "Subscribe" screen, opens pricing URL; drop `BillingClient` dependency.
- Modify `Sources/BogiApp/UI/LoginView.swift` — subscription-required copy.
- Create `Sources/BogiApp/UI/GateView.swift` — switches Login/Subscribe/Blocked/Checking.
- Modify `Sources/BogiApp/AppDelegate.swift` — run the gate at launch; move post-gate startup into `startMainExperience()`; re-check on activate.
- Delete `Sources/BogiApp/Infrastructure/Billing/BillingClient.swift` — unused after PaywallView decouples.
- Create `Tests/BogiAppTests/AccountGateTests.swift` and `Tests/BogiAppTests/GateStateTests.swift`.

---

# Phase A — Backend (paid-only, single price)

Run backend tests with: `cd backend && node --test`

### Task A1: Single-price checkout form builder

**Files:**
- Modify: `backend/src/handler.mjs` (extract from `stripeCheckout`, ~112-143; constants ~15-16)
- Test: `backend/test/infer.test.mjs`

- [ ] **Step 1: Write the failing test**

Add to `backend/test/infer.test.mjs`:

```javascript
import { buildCheckoutForm } from "../src/handler.mjs";

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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test`
Expected: FAIL — `buildCheckoutForm` is not exported / not a function.

- [ ] **Step 3: Implement the helper and wire it in**

In `backend/src/handler.mjs`, replace the two-price constants (lines ~15-16):

```javascript
const STRIPE_PRICE_ID = process.env.STRIPE_PRICE_ID || "";
```

Add the exported pure builder (near `buildInferResponse`):

```javascript
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
```

Rewrite `stripeCheckout` (lines ~112-143) to use it and drop the `plan` param:

```javascript
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
```

Update `planFromPrice` (lines ~305-311) to the single price:

```javascript
// Canonical plan name from the price id we configured, not the editable Stripe nickname.
function planFromPrice(obj) {
  const priceId = obj.items?.data?.[0]?.price?.id || obj.plan?.id || null;
  if (priceId && priceId === STRIPE_PRICE_ID) return "pro";
  return "pro";
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test`
Expected: PASS for both `buildCheckoutForm` tests and the existing `buildInferResponse` test.

- [ ] **Step 5: Commit**

```bash
git add backend/src/handler.mjs backend/test/infer.test.mjs
git commit -m "feat(backend): single-price Stripe checkout via buildCheckoutForm"
```

---

### Task A2: Paid-only inference gate

**Files:**
- Modify: `backend/src/handler.mjs` (`infer` ~69-94; remove `consumeFreeCredit` ~315-335, `usageToday` ~337-346, `FREE_DAILY_LIMIT` ~21)
- Test: `backend/test/infer.test.mjs`

- [ ] **Step 1: Write the failing test**

Add to `backend/test/infer.test.mjs`:

```javascript
import { subscriptionGate } from "../src/handler.mjs";

test("subscriptionGate blocks unpaid users with 403", () => {
  const g = subscriptionGate(false);
  assert.equal(g.allow, false);
  assert.equal(g.status, 403);
  assert.deepEqual(g.body, { error: "subscription_required" });
});

test("subscriptionGate allows paid users", () => {
  const g = subscriptionGate(true);
  assert.equal(g.allow, true);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test`
Expected: FAIL — `subscriptionGate` is not exported.

- [ ] **Step 3: Implement the gate and rewrite `infer`**

Add the exported pure helper (near `buildInferResponse`):

```javascript
// Paid-only access decision. Pure + exported for tests.
export function subscriptionGate(paid) {
  if (!paid) return { allow: false, status: 403, body: { error: "subscription_required" } };
  return { allow: true };
}
```

Rewrite `infer` (lines ~69-94):

```javascript
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
```

Delete the now-unused freemium helpers: `consumeFreeCredit` (~315-335), `usageToday` (~337-346), and the `FREE_DAILY_LIMIT` constant (~21).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test`
Expected: PASS for `subscriptionGate` tests; existing tests still pass.

- [ ] **Step 5: Verify no dangling references**

Run: `cd backend && grep -n "FREE_DAILY_LIMIT\|consumeFreeCredit\|usageToday\|freeRemaining" src/handler.mjs`
Expected: only matches inside `accountStatus` (handled in Task A3) — no calls to the deleted helpers remain in `infer`.

- [ ] **Step 6: Commit**

```bash
git add backend/src/handler.mjs backend/test/infer.test.mjs
git commit -m "feat(backend): paid-only /v1/infer (403 subscription_required), drop freemium quota"
```

---

### Task A3: Slim `/v1/account/status`

**Files:**
- Modify: `backend/src/handler.mjs` (`accountStatus` ~98-108)
- Test: `backend/test/infer.test.mjs`

- [ ] **Step 1: Write the failing test**

Add to `backend/test/infer.test.mjs`:

```javascript
import { buildAccountStatus } from "../src/handler.mjs";

test("buildAccountStatus returns paid, plan, userId only", () => {
  const body = buildAccountStatus({ paid: true, plan: "pro", userId: "u1" });
  assert.deepEqual(body, { paid: true, plan: "pro", userId: "u1" });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && node --test`
Expected: FAIL — `buildAccountStatus` is not exported.

- [ ] **Step 3: Implement and wire in**

Add the exported helper:

```javascript
export function buildAccountStatus({ paid, plan, userId }) {
  return { paid, plan, userId };
}
```

Rewrite `accountStatus` (lines ~98-108):

```javascript
async function accountStatus(event) {
  const user = await authUser(event);
  if (!user) return json(401, { error: "unauthorized" });
  const { paid, plan } = await fetchProfile(user.id);
  return json(200, buildAccountStatus({ paid, plan, userId: user.id }));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && node --test`
Expected: PASS. Then confirm cleanup: `grep -n "FREE_DAILY_LIMIT\|freeRemaining\|usageToday\|consumeFreeCredit" src/handler.mjs` returns nothing.

- [ ] **Step 5: Commit**

```bash
git add backend/src/handler.mjs backend/test/infer.test.mjs
git commit -m "feat(backend): slim /v1/account/status to {paid,plan,userId}"
```

---

### Task A4: Remove freemium SQL + fix deploy env

**Files:**
- Delete: `backend/supabase/ai_usage.sql`
- Modify: `backend/deploy.sh:34`

- [ ] **Step 1: Delete the freemium SQL**

```bash
git rm backend/supabase/ai_usage.sql
```

- [ ] **Step 2: Update the deploy env passthrough**

In `backend/deploy.sh` line 34, replace the env key list so it carries the single price and drops the freemium/annual keys. Change:

```javascript
for (const k of ["SUPABASE_URL","SUPABASE_ANON_KEY","SUPABASE_SERVICE_KEY","STRIPE_SECRET_KEY","STRIPE_WEBHOOK_SECRET","STRIPE_PRICE_MONTHLY","STRIPE_PRICE_ANNUAL","CHECKOUT_SUCCESS_URL","CHECKOUT_CANCEL_URL","BILLING_RETURN_URL","FREE_DAILY_LIMIT"]) if (process.env[k]) v[k] = process.env[k];
```

to:

```javascript
for (const k of ["SUPABASE_URL","SUPABASE_ANON_KEY","SUPABASE_SERVICE_KEY","STRIPE_SECRET_KEY","STRIPE_WEBHOOK_SECRET","STRIPE_PRICE_ID","CHECKOUT_SUCCESS_URL","CHECKOUT_CANCEL_URL","BILLING_RETURN_URL"]) if (process.env[k]) v[k] = process.env[k];
```

- [ ] **Step 3: Verify backend tests still pass**

Run: `cd backend && node --test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add backend/deploy.sh
git commit -m "chore(backend): drop ai_usage.sql + freemium/annual deploy env, add STRIPE_PRICE_ID"
```

---

# Phase B — macOS app (launch gate)

Run app tests with: `cd apps/macos/Bogi && swift test`
Build with: `cd apps/macos/Bogi && swift build`

### Task B1: Website URLs config

**Files:**
- Create: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/AI/WebsiteConfig.swift`

- [ ] **Step 1: Create the config**

```swift
import Foundation

/// Marketing/billing site. Subscriptions are created and managed on the web (website-first);
/// the app only ever opens these URLs in the browser.
enum WebsiteConfig {
    static let pricingURL = URL(string: "https://heytogi.com/pricing")!
    static let accountURL = URL(string: "https://heytogi.com/account")!
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd apps/macos/Bogi && swift build`
Expected: builds (warnings about unused symbol are fine).

- [ ] **Step 3: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Infrastructure/AI/WebsiteConfig.swift
git commit -m "feat(app): WebsiteConfig with pricing/account URLs"
```

---

### Task B2: AccountGate — rich outcome + injectable transport

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Auth/AccountGate.swift`
- Test: `apps/macos/Bogi/Tests/BogiAppTests/AccountGateTests.swift`

- [ ] **Step 1: Write the failing test**

Create `apps/macos/Bogi/Tests/BogiAppTests/AccountGateTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class AccountGateTests: XCTestCase {
    private func gate(token: String?, respond: @escaping (URLRequest) async throws -> (Data, URLResponse)) -> AccountGate {
        AccountGate(baseURL: URL(string: "https://example.com")!,
                    tokenProvider: { token },
                    transport: respond)
    }

    private func http(_ code: Int, _ json: String) -> (Data, URLResponse) {
        let resp = HTTPURLResponse(url: URL(string: "https://example.com/v1/account/status")!,
                                   statusCode: code, httpVersion: nil, headerFields: nil)!
        return (Data(json.utf8), resp)
    }

    func testSignedOutWhenNoToken() async {
        let g = gate(token: nil) { _ in (Data(), URLResponse()) }
        let out = await g.check()
        XCTAssertEqual(out, .signedOut)
    }

    func testSubscribedWhenPaidTrue() async {
        let g = gate(token: "t") { [self] _ in http(200, #"{"paid":true,"plan":"pro"}"#) }
        let out = await g.check()
        XCTAssertEqual(out, .subscribed)
    }

    func testNotSubscribedWhenPaidFalse() async {
        let g = gate(token: "t") { [self] _ in http(200, #"{"paid":false,"plan":null}"#) }
        let out = await g.check()
        XCTAssertEqual(out, .notSubscribed)
    }

    func testSignedOutOn401() async {
        let g = gate(token: "t") { [self] _ in http(401, #"{"error":"unauthorized"}"#) }
        let out = await g.check()
        XCTAssertEqual(out, .signedOut)
    }

    func testUnreachableOnThrow() async {
        struct Boom: Error {}
        let g = gate(token: "t") { _ in throw Boom() }
        let out = await g.check()
        XCTAssertEqual(out, .unreachable)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/macos/Bogi && swift test --filter AccountGateTests`
Expected: FAIL to compile — `GateOutcome`, the `transport:` init param, and `check()` don't exist yet.

- [ ] **Step 3: Rewrite AccountGate**

Replace the contents of `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Auth/AccountGate.swift`:

```swift
import Foundation

/// The four states the subscription gate can resolve to. `unreachable` is distinct from
/// `notSubscribed` so the app can show a Retry screen (strict online check) rather than
/// wrongly telling a paying user to subscribe when the network is down.
enum GateOutcome: Equatable {
    case subscribed
    case notSubscribed
    case signedOut
    case unreachable
}

/// Checks subscription status against the backend. Togi is subscription-first: only signed-in
/// users with an active subscription may use the app.
final class AccountGate {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    struct Status: Decodable { let paid: Bool; let plan: String? }

    private let baseURL: URL
    private let tokenProvider: () async -> String?
    private let transport: Transport

    init(baseURL: URL = BackendConfig.baseURL,
         auth: SupabaseAuth,
         transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.baseURL = baseURL
        self.tokenProvider = { await auth.currentAccessToken() }
        self.transport = transport
    }

    /// Test seam: inject the token provider + transport directly.
    init(baseURL: URL,
         tokenProvider: @escaping () async -> String?,
         transport: @escaping Transport) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.transport = transport
    }

    /// Strict online check. Never silently treats an error as "not subscribed".
    func check() async -> GateOutcome {
        guard let token = await tokenProvider() else { return .signedOut }
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/account/status"))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "X-Bogi-Authorization")
        do {
            let (data, resp) = try await transport(req)
            guard let http = resp as? HTTPURLResponse else { return .unreachable }
            switch http.statusCode {
            case 200:
                guard let status = try? JSONDecoder().decode(Status.self, from: data) else { return .unreachable }
                return status.paid ? .subscribed : .notSubscribed
            case 401:
                return .signedOut
            default:
                return .unreachable
            }
        } catch {
            return .unreachable
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/macos/Bogi && swift test --filter AccountGateTests`
Expected: PASS (all five cases).

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Infrastructure/Auth/AccountGate.swift apps/macos/Bogi/Tests/BogiAppTests/AccountGateTests.swift
git commit -m "feat(app): AccountGate.check() resolves subscribed/notSubscribed/signedOut/unreachable"
```

---

### Task B3: Gate state reducer

**Files:**
- Create: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Auth/GateState.swift`
- Test: `apps/macos/Bogi/Tests/BogiAppTests/GateStateTests.swift`

- [ ] **Step 1: Write the failing test**

Create `apps/macos/Bogi/Tests/BogiAppTests/GateStateTests.swift`:

```swift
import XCTest
@testable import BogiApp

final class GateStateTests: XCTestCase {
    func testMapping() {
        XCTAssertEqual(GateState(for: .subscribed), .unlocked)
        XCTAssertEqual(GateState(for: .notSubscribed), .needsSubscription)
        XCTAssertEqual(GateState(for: .signedOut), .needsLogin)
        XCTAssertEqual(GateState(for: .unreachable), .blocked)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/macos/Bogi && swift test --filter GateStateTests`
Expected: FAIL to compile — `GateState` does not exist.

- [ ] **Step 3: Implement the reducer**

Create `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Auth/GateState.swift`:

```swift
import Foundation

/// What the launch gate should show. `checking` is the initial state before the first
/// `AccountGate.check()` resolves.
enum GateState: Equatable {
    case checking
    case needsLogin
    case needsSubscription
    case blocked          // signed in + subscribed unknown (offline / server error)
    case unlocked

    init(for outcome: GateOutcome) {
        switch outcome {
        case .subscribed:    self = .unlocked
        case .notSubscribed: self = .needsSubscription
        case .signedOut:     self = .needsLogin
        case .unreachable:   self = .blocked
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/macos/Bogi && swift test --filter GateStateTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Infrastructure/Auth/GateState.swift apps/macos/Bogi/Tests/BogiAppTests/GateStateTests.swift
git commit -m "feat(app): GateState reducer mapping GateOutcome to UI state"
```

---

### Task B4: Map backend 403 to subscriptionRequired

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/AI/InferenceClient.swift`

- [ ] **Step 1: Update the error case**

In `InferenceClient.swift`, replace the `paymentRequired` case (lines ~19-22) in `enum InferenceError`:

```swift
    /// 403 from the backend: the user has no active subscription. The UI should react by
    /// re-running the launch gate and showing the Subscribe screen, not a generic error.
    case subscriptionRequired
```

Remove the now-unused `QuotaError` struct (lines ~61-65) and rewrite the non-2xx branch in `infer` (lines ~83-89):

```swift
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if http.statusCode == 403 { throw InferenceError.subscriptionRequired }
            throw InferenceError.badStatus(http.statusCode)
        }
```

- [ ] **Step 2: Find and fix callers of the old case**

Run: `cd apps/macos/Bogi && grep -rn "paymentRequired" Sources Tests`
Expected: any matches are in catch-sites; update each `catch InferenceError.paymentRequired` to `catch InferenceError.subscriptionRequired`. (If none, continue.)

- [ ] **Step 3: Build to verify**

Run: `cd apps/macos/Bogi && swift build`
Expected: builds with no reference to `paymentRequired` or `QuotaError`.

- [ ] **Step 4: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Infrastructure/AI/InferenceClient.swift
git commit -m "feat(app): map backend 403 to InferenceError.subscriptionRequired"
```

---

### Task B5: Subscribe screen (PaywallView) — single plan, opens website

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/UI/PaywallView.swift`
- Delete: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Billing/BillingClient.swift`

- [ ] **Step 1: Rewrite PaywallView as a single-plan Subscribe screen**

Replace the contents of `apps/macos/Bogi/Sources/BogiApp/UI/PaywallView.swift`:

```swift
import SwiftUI

/// Shown to a signed-in user without an active subscription. Website-first: the subscribe
/// button opens the pricing page in the browser; payment completion arrives via the Stripe
/// webhook, so the gate re-checks when the app regains focus. Rendering-only: actions injected.
struct PaywallView: View {
    /// Opens the website pricing page in the browser.
    let onSubscribe: () -> Void
    /// Re-run the gate (e.g. after subscribing on the web and returning).
    var onRecheck: () -> Void = {}
    /// Sign out / use a different account.
    var onSignOut: () -> Void = {}

    private let features = [
        "Always-on focus tracking, all day",
        "Automatic replanning when you fall behind",
        "Coaching that learns your patterns",
        "Unlimited nudges and focus blocks",
    ]

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                BogiAsset.mascot
                    .resizable().scaledToFit()
                    .frame(width: 54, height: 54)
                Text("Subscribe to unlock Togi")
                    .font(.title3).bold()
                    .multilineTextAlignment(.center)
                Text("Let Togi run your whole day, not just sit with you for it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(features, id: \.self) { feature in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(BogiColor.primary)
                            .font(.system(size: 13))
                        Text(feature).font(.subheadline)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onSubscribe) {
                Text("Subscribe on the website").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("I've subscribed — check again", action: onRecheck)
                .buttonStyle(.link)
                .font(.caption)

            Button("Sign out", action: onSignOut)
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(26)
        .frame(width: 340)
    }
}

#if DEBUG
#Preview("Subscribe") {
    PaywallView(onSubscribe: {}, onRecheck: {}, onSignOut: {})
        .background(Color(white: 0.12))
}
#endif
```

- [ ] **Step 2: Delete the now-unused BillingClient**

```bash
git rm apps/macos/Bogi/Sources/BogiApp/Infrastructure/Billing/BillingClient.swift
```

- [ ] **Step 3: Build to verify**

Run: `cd apps/macos/Bogi && swift build`
Expected: builds. Confirm nothing else references BillingClient: `grep -rn "BillingClient" Sources Tests` returns nothing.

- [ ] **Step 4: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/UI/PaywallView.swift
git commit -m "feat(app): single-plan Subscribe screen opening website; remove BillingClient"
```

---

### Task B6: LoginView copy

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/UI/LoginView.swift`

- [ ] **Step 1: Update the copy**

In `LoginView.swift`, change the subtitle (line ~24) from:

```swift
                Text("Free to start. No card needed.")
```

to:

```swift
                Text("Togi requires an active subscription.")
```

And change the bottom link (line ~60) from:

```swift
            Button("Manage subscription on the website", action: openWebsite)
```

to:

```swift
            Button("Need an account? Subscribe on the website", action: openWebsite)
```

- [ ] **Step 2: Build to verify**

Run: `cd apps/macos/Bogi && swift build`
Expected: builds (signature of `LoginView` unchanged, so existing Settings callers still compile).

- [ ] **Step 3: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/UI/LoginView.swift
git commit -m "feat(app): subscription-required copy in LoginView"
```

---

### Task B7: GateView — switch between gate states

**Files:**
- Create: `apps/macos/Bogi/Sources/BogiApp/UI/GateView.swift`

- [ ] **Step 1: Create the view**

```swift
import SwiftUI

/// Full-window gate shown before the app unlocks. Pure rendering — every action and the
/// current state are injected by the AppDelegate's gate controller.
struct GateView: View {
    let state: GateState
    let signIn: (String, String) async throws -> Void
    let openWebsite: () -> Void
    let onSubscribe: () -> Void
    let onRecheck: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        switch state {
        case .checking:
            VStack(spacing: 12) {
                ProgressView()
                Text("Checking your subscription…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(40).frame(width: 340)
        case .needsLogin:
            LoginView(signIn: signIn, openWebsite: openWebsite)
        case .needsSubscription:
            PaywallView(onSubscribe: onSubscribe, onRecheck: onRecheck, onSignOut: onSignOut)
        case .blocked:
            VStack(spacing: 14) {
                BogiAsset.mascot.resizable().scaledToFit().frame(width: 48, height: 48)
                Text("Can't reach Togi right now")
                    .font(.headline)
                Text("Check your connection and try again.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Retry", action: onRecheck)
                    .buttonStyle(.borderedProminent)
                Button("Sign out", action: onSignOut)
                    .buttonStyle(.link).font(.caption)
            }
            .padding(32).frame(width: 340)
        case .unlocked:
            EmptyView()
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `cd apps/macos/Bogi && swift build`
Expected: builds.

- [ ] **Step 3: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/UI/GateView.swift
git commit -m "feat(app): GateView switching Checking/Login/Subscribe/Blocked"
```

---

### Task B8: GateController — owns state, runs the check

**Files:**
- Create: `apps/macos/Bogi/Sources/BogiApp/Infrastructure/Auth/GateController.swift`

- [ ] **Step 1: Create the controller**

```swift
import SwiftUI

/// Drives the launch gate: holds the current GateState, runs the strict online check, and
/// exposes sign-in. The AppDelegate observes `state` to decide whether to show the gate
/// window or start the main experience.
@MainActor
final class GateController: ObservableObject {
    @Published private(set) var state: GateState = .checking

    private let auth: SupabaseAuth
    private let gate: AccountGate

    init(auth: SupabaseAuth, gate: AccountGate) {
        self.auth = auth
        self.gate = gate
    }

    /// Re-run the subscription check and publish the resulting state.
    func refresh() async {
        state = .checking
        let outcome = await gate.check()
        state = GateState(for: outcome)
    }

    func signIn(email: String, password: String) async throws {
        try await auth.signIn(email: email, password: password)
        await refresh()
    }

    func signOut() {
        auth.signOut()
        state = .needsLogin
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `cd apps/macos/Bogi && swift build`
Expected: builds.

- [ ] **Step 3: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/Infrastructure/Auth/GateController.swift
git commit -m "feat(app): GateController owns gate state + sign-in/refresh"
```

---

### Task B9: Wire the gate into the launch lifecycle

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/AppDelegate.swift`

This task moves the post-gate startup into `startMainExperience()` and shows a gate window until `state == .unlocked`.

- [ ] **Step 1: Add gate window + controller properties**

In `AppDelegate` (after `private var calmScheduler` ~153) add:

```swift
    private var gateWindow: NSWindow?
    private lazy var gate = GateController(auth: appState.auth, gate: appState.accountGate)
    private var gateObservation: AnyCancellable?
    private var mainExperienceStarted = false
```

Add at the top of the file (with the other imports):

```swift
import Combine
```

- [ ] **Step 2: Split `applicationDidFinishLaunching` so startup is gated**

In `applicationDidFinishLaunching`, keep the two demo-hook early returns (`BOGI_SHOW_CALM`, `BOGI_SHOW_COMPANION`) and the `NSApp.setActivationPolicy(.accessory)` line. Then **replace everything from `if appState.capture.permissionState != .granted` through the end of the method** with a call to start the gate:

```swift
        // Gate the whole app on a signed-in, subscribed user (strict online check).
        gateObservation = gate.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.applyGateState(state) }
        Task { await gate.refresh() }
```

- [ ] **Step 3: Add the gate presentation + startup transition methods**

Add these methods to `AppDelegate` (e.g. after `applicationDidFinishLaunching`):

```swift
    private func applyGateState(_ state: GateState) {
        if state == .unlocked {
            gateWindow?.orderOut(nil)
            gateWindow = nil
            startMainExperienceIfNeeded()
        } else {
            showGateWindow(for: state)
        }
    }

    private func showGateWindow(for state: GateState) {
        let view = GateView(
            state: state,
            signIn: { [weak self] email, pw in try await self?.gate.signIn(email: email, password: pw) },
            openWebsite: { NSWorkspace.shared.open(WebsiteConfig.pricingURL) },
            onSubscribe: { NSWorkspace.shared.open(WebsiteConfig.pricingURL) },
            onRecheck: { [weak self] in Task { await self?.gate.refresh() } },
            onSignOut: { [weak self] in self?.gate.signOut() }
        )
        if let win = gateWindow {
            win.contentViewController = NSHostingController(rootView: view)
        } else {
            let win = NSWindow(contentViewController: NSHostingController(rootView: view))
            win.styleMask = [.titled, .closable]
            win.title = "Togi"
            win.isReleasedWhenClosed = false
            win.center()
            gateWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        gateWindow?.makeKeyAndOrderFront(nil)
    }

    /// Everything that used to run unconditionally in applicationDidFinishLaunching — now only
    /// after the gate unlocks, and only once.
    private func startMainExperienceIfNeeded() {
        guard !mainExperienceStarted else { return }
        mainExperienceStarted = true
        startMainExperience()
    }
```

- [ ] **Step 4: Create `startMainExperience()` from the old startup body**

Add a new method `startMainExperience()` containing exactly the code you removed in Step 2 (capture permission/start, mascot setup, `SidecarActionHandlers` wiring, `appState.sidecar.tokenProvider`, `Task { await self.appState.startSidecar() }`, `JudgeCoordinator`, `openDashboard`/`runJudgeNow`, `CalendarSyncCoordinator`, calm hooks, `CalmScheduler`). Wrap it as:

```swift
    private func startMainExperience() {
        if appState.capture.permissionState != .granted {
            appState.capture.requestPermission()
        }
        appState.capture.start()
        // ... (the rest of the original startup body, verbatim) ...
    }
```

- [ ] **Step 5: Re-check on activation (strict, drops to Subscribe on lapse)**

Add the delegate method so a subscription lapse or returning from the web re-runs the gate:

```swift
    func applicationDidBecomeActive(_ notification: Notification) {
        guard mainExperienceStarted || gateWindow != nil else { return }
        Task { await gate.refresh() }
    }
```

Note: when the gate later resolves to `.needsSubscription`/`.blocked` after unlock, `applyGateState` shows the gate window again over the running app; inference is independently blocked server-side (403). Full teardown of the running experience on lapse is out of scope (the server gate is the real enforcement).

- [ ] **Step 6: Build**

Run: `cd apps/macos/Bogi && swift build`
Expected: builds with no errors.

- [ ] **Step 7: Run the full test suite**

Run: `cd apps/macos/Bogi && swift test`
Expected: PASS (AccountGateTests, GateStateTests, and all pre-existing tests).

- [ ] **Step 8: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/AppDelegate.swift
git commit -m "feat(app): gate launch on signed-in + subscribed; re-check on activate"
```

---

### Task B10: Point the in-Settings sign-in website links at heytogi

**Files:**
- Modify: `apps/macos/Bogi/Sources/BogiApp/UI/SettingsView.swift:22`
- Modify: `apps/macos/Bogi/Sources/BogiApp/UI/CompanionSettingsView.swift` (the `openWebsite:` closure ~36)

- [ ] **Step 1: Replace the stale `bogi.sh` URL**

In `SettingsView.swift` line ~22, change:

```swift
                openWebsite: { NSWorkspace.shared.open(URL(string: "https://bogi.sh/account")!) }
```

to:

```swift
                openWebsite: { NSWorkspace.shared.open(WebsiteConfig.accountURL) }
```

In `CompanionSettingsView.swift`, change its `openWebsite:` closure body to `NSWorkspace.shared.open(WebsiteConfig.accountURL)` (match the existing closure shape; read lines ~32-40 first to preserve surrounding syntax).

- [ ] **Step 2: Build to verify**

Run: `cd apps/macos/Bogi && swift build`
Expected: builds. Confirm no stale domain remains: `grep -rn "bogi.sh" Sources` returns nothing.

- [ ] **Step 3: Commit**

```bash
git add apps/macos/Bogi/Sources/BogiApp/UI/SettingsView.swift apps/macos/Bogi/Sources/BogiApp/UI/CompanionSettingsView.swift
git commit -m "chore(app): point account links at heytogi.com via WebsiteConfig"
```

---

# Phase C — Verification

### Task C1: Full automated verification

- [ ] **Step 1: Backend tests**

Run: `cd backend && node --test`
Expected: all tests PASS, including `buildCheckoutForm`, `subscriptionGate`, `buildAccountStatus`, `buildInferResponse`.

- [ ] **Step 2: macOS build + tests**

Run: `cd apps/macos/Bogi && swift build && swift test`
Expected: build succeeds; all tests PASS.

- [ ] **Step 3: Grep for removed concepts**

Run:
```bash
grep -rn "FREE_DAILY_LIMIT\|consumeFreeCredit\|freeRemaining\|STRIPE_PRICE_MONTHLY\|STRIPE_PRICE_ANNUAL" backend/src backend/deploy.sh
grep -rn "BillingClient\|paymentRequired\|bogi.sh" apps/macos/Bogi/Sources
```
Expected: no matches (all freemium/two-price/old-domain references gone).

### Task C2: Manual E2E (Stripe test mode) — checklist for the operator

Not code; record the result of each in the PR description.

- [ ] Supabase dashboard: set **Auth → Email → Confirm email = OFF** (`mailer_autoconfirm: true`).
- [ ] Deploy backend with `AUTH_DISABLED=0`, `SUPABASE_*`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PRICE_ID` set (`cd backend && ./deploy.sh`).
- [ ] Create a test account via Supabase signup (or the website) → `profiles` row appears, `paid=false`.
- [ ] Launch the app, sign in → **Subscribe screen** appears (paid=false). Asking the coach is blocked.
- [ ] Subscribe via the website pricing page with card `4242 4242 4242 4242` → Stripe webhook flips `profiles.paid=true`.
- [ ] Re-focus the app → gate re-checks → app **unlocks**; the coach answers.
- [ ] Cancel via Stripe portal/dashboard → `customer.subscription.deleted` → `paid=false`; on next app focus the **Subscribe screen** returns and `/v1/infer` returns 403.

---

## Self-review notes (author)

- **Spec coverage:** paid-only infer (A2), single price (A1, A4), slim status (A3), remove ai_usage (A4), auto-confirm (C2 manual step + spec go-live), launch gate with strict check + four states (B2,B3,B7,B8,B9), 403 handling (B4, B9 step 5), subscribe-opens-website (B5, B9), LoginView copy (B6), website contract (documented in spec; out of scope here). All covered.
- **Auto-confirm** is a Supabase dashboard setting (no code) — captured as a verification/go-live step (C2), consistent with the spec.
- **Type consistency:** `GateOutcome` (B2) → `GateState(for:)` (B3) → `GateController.state` (B8) → `GateView`/`applyGateState` (B7,B9); `InferenceError.subscriptionRequired` (B4) used in B9 note; `WebsiteConfig.pricingURL/accountURL` (B1) used in B5/B9/B10.
