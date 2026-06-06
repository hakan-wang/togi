# Subscription account sync + subscription-gated macOS login — design

**Date:** 2026-06-06
**Status:** Approved (brainstorming) — ready for implementation plan

## Goal

Make Togi a **subscription-only** product: users create an account and pay on the
website (heytogi.com), that subscription syncs to Supabase, and the macOS app unlocks
**only** for a signed-in user with an active subscription. There is **no free tier**.

## Locked decisions

| Decision | Choice |
|---|---|
| Access model | **Subscription-only** — no freemium quota |
| Signup/payment | **Website-first** — account + payment happen on heytogi.com; app is sign-in only |
| Pricing | **Single plan** (one `STRIPE_PRICE_ID`, matching what is live in Stripe) |
| Gate strictness | **Strict online check** — a successful server check is required to use the app; no offline use |
| Email confirmation | **Auto-confirm** (`mailer_autoconfirm: true`) — accounts work immediately after signup |
| In-app subscribe | Button **opens the website pricing page** in the browser (no in-app Stripe Checkout) |
| Website (heytogi.com) | **Out of scope** — this spec defines the contract it must meet, nothing more |

## Source-of-truth model

- **Supabase `profiles.paid`** = "who may use the app." The app reads this only through the
  backend; the client is never trusted.
- **Stripe** = "who is paying." Stripe pushes changes to Supabase via the backend webhook.
- The backend (AWS Lambda) is the only component holding the Supabase service key and Stripe
  secret key.

## End-to-end flow (account-first)

```
Website (heytogi.com — out of scope)   Backend (AWS Lambda)        Supabase           Stripe
────────────────────────────────────   ────────────────────        ────────           ──────
1. signup(email,pw) ─────────────────────────────────────────────▶ auth.users
                                                                    + profiles row
                                                                    (auto-confirmed,
                                                                     paid=false)
2. POST /v1/stripe/checkout ──────────▶ create Checkout Session ────────────────────▶ hosted pay page
   (Authorization: user access token)
3. user pays ───────────────────────────────────────────────────────────────────────▶ ✓
4.                                      POST /v1/stripe/webhook ◀──────────────────────  subscription.*
                                        sets profiles.paid=true
                                        + stripe_customer_id ─────▶ profiles
5. Mac app: sign in (email,pw) ───────▶ GET /v1/account/status ───▶ reads profiles
                                        {paid:true} → UNLOCK
```

## Website contract (NOT built here — heytogi.com must satisfy)

1. **Sign up** via Supabase `POST /auth/v1/signup` (anon key). With auto-confirm enabled the
   account is immediately usable; the `on_auth_user_created` trigger creates the `profiles`
   row (`paid=false`).
2. **Subscribe**: with the user's Supabase access token, call backend
   `POST /v1/stripe/checkout` and redirect the user to the returned hosted Stripe URL.
3. **Pricing page** at a stable URL (e.g. `https://heytogi.com/pricing`) — the macOS app's
   in-app "Subscribe" button opens this.
4. (Optional) **Manage subscription**: call `POST /v1/stripe/portal` or link to Stripe's
   customer portal.

## Component changes

### Backend (`backend/src/handler.mjs`)

- **`/v1/infer` → paid-only.** Remove the freemium branch (`consumeFreeCredit`, `usageToday`,
  `freeRemaining`, `FREE_DAILY_LIMIT`). If `profiles.paid` is false, return
  `403 { error: "subscription_required" }`. Paid users proceed unchanged.
- **Single price.** Replace `STRIPE_PRICE_MONTHLY` / `STRIPE_PRICE_ANNUAL` with one
  `STRIPE_PRICE_ID`. Drop the `plan` request param and the annual branch in `stripeCheckout`.
  `planFromPrice` collapses to a single known price → `"pro"`.
- **`/v1/account/status`.** Return `{ paid, plan, userId }` only — drop `freeLimit` /
  `freeRemaining`.
- **Webhook unchanged.** `stripeWebhook` (signature verification, id validation, customer-id
  vs metadata binding, retry-on-failed-write) is correct and stays as-is.
- **Tests** (`backend/test/infer.test.mjs`): update to assert paid-only gating (403 for
  unpaid, 200 for paid); remove freemium-quota assertions.

### Supabase (project `qpbmrmmnojpqwcaxmqww`)

- **`profiles`** already deployed (`backend/supabase/profiles.sql`) — no change.
- **Enable auto-confirm**: set `mailer_autoconfirm = true` (Dashboard → Auth → or
  management API). Documented in the go-live checklist.
- **Remove `backend/supabase/ai_usage.sql`** — freemium-only; the `ai_usage` table is not
  deployed and is not needed. Deleting the file avoids it being applied by mistake.
- The orphaned Supabase Edge-Function Stripe secrets (`STRIPE_SECRET_KEY`,
  `STRIPE_WEBHOOK_SECRET`, `STRIPE_PRICE_ID`) are read by nothing (no Edge Functions
  deployed). The **AWS Lambda** is the real handler and reads its own env. Action: ensure the
  Lambda env (via `backend/deploy.sh`) carries `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`,
  `STRIPE_PRICE_ID`, `AUTH_DISABLED=0`. Leaving the Supabase secrets in place is harmless;
  optionally delete them to reduce confusion.

### macOS app (`apps/macos/Bogi`)

The app already has `SupabaseAuth`, `AccountGate`, `LoginView`, `PaywallView`,
`BillingClient`, and a valid anon key — but **none of the gating is wired into the launch
lifecycle**. This is the bulk of the work.

- **Launch/wake gate** (in `AppDelegate`), strict online check:
  - No Keychain session → show `LoginView`.
  - Signed in → call `AccountGate` (`GET /v1/account/status`):
    - success + `paid:true` → unlock the app.
    - success + `paid:false` → show the **Subscribe screen** (repurposed `PaywallView`).
    - failure (offline / 401 / non-200) → show a **blocked screen** with **Retry** and
      re-sign-in. No offline use (strict).
  - Re-verify on app activation / wake.
- **Mid-session lapse**: when `/v1/infer` returns `403 subscription_required` (surface via
  `InferenceError`), re-run the gate and drop the user to the Subscribe screen.
- **Subscribe screen** (`PaywallView`): simplify to a single plan; primary button **opens the
  website pricing page** (`https://heytogi.com/pricing`) via `NSWorkspace`. Drop the annual
  toggle and the in-app `BillingClient.startCheckout` path (no longer used by the primary
  flow).
- **`LoginView` copy**: replace "Free to start. No card needed." with subscription-required
  messaging and a "Subscribe at heytogi.com" link.
- **`BillingClient`**: the in-app checkout/portal HTTP calls are no longer needed by the app
  (subscribe/manage happen on the website). Either remove `BillingClient` or keep only a thin
  URL-opening helper. Recommendation: replace its use with simple `NSWorkspace.open(pricingURL)`.

## Error handling

- Backend: unauthenticated → 401; authenticated but unpaid → 403 `subscription_required`;
  Stripe/Supabase infra errors → 5xx so Stripe retries the webhook (already implemented).
- App: every gate outcome maps to an explicit screen (Login / Subscribe / Blocked-with-retry /
  Unlocked). The app never silently proceeds when the check fails — strict by decision.

## Testing

- **Backend unit tests**: `/v1/infer` returns 403 for unpaid, 200 for paid; `/v1/account/status`
  returns `{paid, plan, userId}`; checkout builds a single-price session. Webhook tests
  unchanged.
- **Manual E2E** (Stripe test mode, card `4242 4242 4242 4242`):
  1. Create account on the website (or via Supabase signup) → `profiles` row, `paid=false`.
  2. Open app, sign in → Subscribe screen (paid=false).
  3. Subscribe on website → pay → webhook flips `paid=true`.
  4. Re-focus app → gate re-checks → app unlocks; inference works.
  5. Cancel via portal → `customer.subscription.deleted` → `paid=false` → app drops to
     Subscribe screen on next check; inference returns 403.

## Out of scope

- The heytogi.com website (signup UI, pricing page, checkout redirect) — separate repo.
- Monthly/annual pricing (single plan now; add the second price later).
- Offline grace period (explicitly rejected: strict online check).
- Freemium / free-tier quota and the `ai_usage` table (removed).
- Social / Apple / Google sign-in (email/password only).

## Go-live checklist (delta from `TOGI_PAYWALL_SETUP.md`)

1. Supabase: set `mailer_autoconfirm = true`. (`profiles` already applied.)
2. Stripe: confirm the single `STRIPE_PRICE_ID`; webhook endpoint configured for
   `customer.subscription.*`, `checkout.session.completed`, `invoice.paid`.
3. Lambda env (`deploy.sh`): `AUTH_DISABLED=0`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
   `SUPABASE_SERVICE_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PRICE_ID`.
4. Ship the macOS app with the launch gate wired.
