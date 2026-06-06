# Togi paywall — go-live guide

This is the freemium paywall: free users get **5 AI calls per UTC day**, then a paywall.
Togi Pro is **$9.99/mo** or **$79/yr** (save 33%), charged immediately, with a **14-day
money-back guarantee** (no Stripe trial — we just refund on request). All enforcement is
server-side; the client is never trusted.

Decisions locked with Michelle on 2026-06-06: model = freemium taste-then-wall, currency =
USD, free quota = essentially unlimited for now (one-line knob: `FREE_DAILY_LIMIT`, default 100000 — we want users; tighten later), risk reversal = money-back
guarantee instead of a trial.

---

## What's already built (in this change)

**Backend** (`backend/src/handler.mjs`)
- `POST /v1/stripe/checkout` — creates a Stripe Checkout Session for the signed-in user
  (subscription mode, `client_reference_id` + `subscription_data.metadata.supabase_user_id`
  so the webhook can map Stripe → Supabase). Body `{ "plan": "monthly" | "annual" }`.
- `POST /v1/stripe/portal` — opens the Customer Portal for the user's `stripe_customer_id`.
- `POST /v1/infer` — gating changed from **paid-only** to **paid OR under the daily free
  quota**. Free users get `FREE_DAILY_LIMIT` calls/day, then `402 { error: "quota_exhausted",
  limit, used }`. Paid users are unlimited.
- `POST /v1/stripe/webhook` — now also persists `stripe_customer_id` and reads subscription
  `status`, and falls back to matching by customer id for events without our metadata
  (e.g. `invoice.paid` renewals).
- `GET /v1/account/status` — now also returns `freeLimit` and `freeRemaining` for free users.

**Database** (`backend/supabase/ai_usage.sql`) — new `ai_usage` table + atomic
`consume_ai_credit(uid, day, max)` RPC (increments only while under the cap), plus an index on
`profiles.stripe_customer_id`. Lives in the **same** Supabase project as `profiles.sql`.

**macOS app**
- `Infrastructure/Billing/BillingClient.swift` (new) — calls checkout/portal, opens the
  hosted Stripe URL in the browser.
- `UI/PaywallView.swift` (new) — the upsell screen (price, annual toggle, money-back line).
- `Infrastructure/AI/InferenceClient.swift` — throws `InferenceError.paymentRequired(used,
  limit)` on 402 so the UI can show the paywall instead of a generic error.
- `UI/LoginView.swift` — copy fixed from "needs an active subscription" to "Free to start."

**Website** (`get-on-my-list`, built + verified, NOT yet deployed)
- `src/routes/pricing.tsx` — real $9.99/mo + $79/yr, money-back guarantee, on-brand.
- `src/routes/upgrade-success.tsx` + `upgrade-cancelled.tsx` — Stripe redirect landing pages.

---

## Go-live steps

### 1. Stripe product + prices
```bash
cd backend
stripe login                 # once (or: export STRIPE_API_KEY=sk_live_... ; LIVE=1)
./stripe-setup.sh            # prints STRIPE_PRICE_MONTHLY and STRIPE_PRICE_ANNUAL
```
In the Stripe dashboard:
- Webhooks → add endpoint `https://e7fsq18rqf.execute-api.eu-west-1.amazonaws.com/v1/stripe/webhook`,
  events: `checkout.session.completed`, `customer.subscription.updated`,
  `customer.subscription.deleted`, `invoice.paid`. Copy the signing secret → `STRIPE_WEBHOOK_SECRET`.
- Settings → Billing → Customer portal → enable (allow cancel + plan switch).

### 2. Database
Open the **app's** Supabase project (`qpbmrmmnojpqwcaxmqww`) → SQL editor, and run:
- `backend/supabase/profiles.sql` (if not already applied)
- `backend/supabase/ai_usage.sql`

### 3. Backend env + deploy
Export these and run `./deploy.sh` (deploy.sh already passes them through):
```bash
export AUTH_DISABLED=0                                              # turn ON real auth/paid
export SUPABASE_URL=https://qpbmrmmnojpqwcaxmqww.supabase.co
export SUPABASE_ANON_KEY=<anon key>
export SUPABASE_SERVICE_KEY=<service role key>                      # secret
export STRIPE_SECRET_KEY=sk_live_...                                # or sk_test_ for testing
export STRIPE_WEBHOOK_SECRET=whsec_...
export STRIPE_PRICE_MONTHLY=price_...
export STRIPE_PRICE_ANNUAL=price_...
# optional, sensible defaults already baked in:
# CHECKOUT_SUCCESS_URL, CHECKOUT_CANCEL_URL, BILLING_RETURN_URL, FREE_DAILY_LIMIT=100000 (essentially unlimited)
./deploy.sh
```

### 4. App wiring (Erik — ~15 lines, the only thing I left for you)
The paywall components are drop-in; they just need presenting. I did not touch the launch
lifecycle / auth wiring since that's mid-stream on your side.

`AppState` (AppDelegate.swift): add a billing client + a hook
```swift
let billing: BillingClient
var openPaywall: (() -> Void)?
// in init(), after `self.inference = ...`:
self.billing = BillingClient(baseURL: BackendConfig.baseURL,
                             tokenProvider: { await auth.currentAccessToken() })
```
`CoachView.swift`: add `var onPaywall: () -> Void = {}` and split the catch in `send`:
```swift
} catch InferenceError.paymentRequired {
    onPaywall()
} catch {
    errorText = "togi couldn't answer: \(error.localizedDescription)"
}
```
`CompanionView.swift`: add `var onPaywall: () -> Void = {}` and pass it into `CoachView(...)`.
`AppDelegate.companionPanel()`: pass `onPaywall: { [weak self] in self?.showPaywall() }` into
`CompanionView`, and add:
```swift
private var paywallWindow: NSWindow?
private func showPaywall() {
    let view = PaywallView(
        startCheckout: { [weak self] plan in try? await self?.appState.billing.startCheckout(plan: plan) },
        openPortal:    { [weak self] in try? await self?.appState.billing.openPortal() },
        onClose:       { [weak self] in self?.paywallWindow?.close() })
    let win = NSWindow(contentViewController: NSHostingController(rootView: view))
    win.styleMask = [.titled, .closable]; win.title = "Togi Pro"
    win.isReleasedWhenClosed = false; win.center()
    NSApp.activate(ignoringOtherApps: true); win.makeKeyAndOrderFront(nil)
    paywallWindow = win
}
// in applicationDidFinishLaunching: appState.openPaywall = { [weak self] in self?.showPaywall() }
```
`MenuBarContent.swift`: add `Button("Upgrade to Togi Pro") { appState.openPaywall?() }`.

When auth is ready: gate the app on `auth` being signed in (not on paid), and after the
browser returns, re-check `accountGate.isPaid()` to unlock unlimited.

### 5. Website (Michelle / clean release)
`get-on-my-list` is built (`npm run build`) and the worker is `heytogi`. Deploy with
`npx wrangler deploy`. NOTE: the working tree currently also holds another session's
uncommitted `__root.tsx` / `index.tsx` / `privacy.tsx` changes, and the privacy page is on
hold for legal-entity facts — deploy from a clean tree so you don't publish it early.

---

## End-to-end test (Stripe test mode, card 4242 4242 4242 4242)
1. Sign in as a test user in the app.
2. Ask the coach 5 times. The 6th returns 402 and the paywall appears.
3. Click Upgrade → browser opens Stripe Checkout → pay → lands on `/upgrade-success`.
4. Webhook flips `profiles.paid = true`; the app now infers without limit.
5. Manage subscription → portal → cancel → `customer.subscription.deleted` flips `paid = false`.

---

## Security hardening (from the pre-go-live audit) + follow-ups

Fixed in this change:
- Webhook rejects replayed/stale events (Stripe timestamp tolerance, ±5 min).
- Webhook binds paid-state to the Stripe `customer` id and refuses to flip a profile already
  tied to a different customer, so one person's payment can't grant/revoke another's Pro.
- All ids are shape-validated (UUID / `cus_…`) and URL-encoded before any query.
- Profile writes are verified (row-count checked / upserted); a failed write returns 5xx so
  Stripe retries, instead of a paid user silently staying unpaid.
- `plan` is derived from our configured price ids, not the editable Stripe nickname.
- Secure by default: `deploy.sh` now defaults `AUTH_DISABLED=0`. For LOCAL dev you must now set
  `AUTH_DISABLED=1` explicitly. `/healthz` reports `authDisabled` so a wide-open deploy is obvious.

Still recommended before scale (not blockers for first test payments):
- Idempotency/ordering: add an `event.id` dedup + ignore out-of-order subscription transitions.
  Boolean flips are largely self-correcting, but a delayed `updated(active)` after a `deleted`
  could briefly re-grant Pro.
- Free-quota backstop: `consume_ai_credit` fails OPEN on a metering outage (kind to users, but
  unmetered). Add an API Gateway throttle as a coarse cost cap behind it.
- Residual cross-user bind: only relevant if you add Payment Links / dashboard sessions / a
  web-initiated checkout. The app-initiated checkout sets the user server-side, so it's safe;
  if you add other entry points, verify the customer email matches the Supabase user.

---

## Merging with Erik's latest (converse.mjs / tool-use)

Erik's branch added `backend/src/converse.mjs` and refactored `callBedrock` to support
tool-use, which changes the `/v1/infer` response shape. When that gets merged with this
paywall work, the ONLY backend conflict is the `/v1/infer` return line. Keep BOTH sides:

    return json(200, { ...buildInferResponse(parsed), paid, freeRemaining });

That preserves his richer response (text, content, stopReason, usage) and the paywall's
metering fields (paid, freeRemaining). The auth + free-quota gate above the return is
unchanged and should stay.
