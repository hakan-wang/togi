# Bogi Backend

A **stateless** AWS Lambda proxy for the Bogi macOS app. It does exactly three
things and **stores no user data**:

1. Forwards inference requests to **AWS Bedrock** (Claude Sonnet 4.6) after
   checking the caller is authenticated and paid.
2. Reports a user's paid status (read from Supabase).
3. Receives Stripe webhooks and flips the user's paid flag in Supabase.

All real user data — captured activity, calendars, the local life-data-bank —
lives **locally on the Mac** and never reaches this backend. The only
cloud-resident user state is a single `profiles` row per account holding the
subscription entitlement.

## Privacy guarantee

- **No user data is stored here.** The Lambda is stateless and scales to zero.
- **Inference content is never logged.** `POST /v1/infer` passes messages
  straight to Bedrock and returns the text; request/response bodies are not
  persisted or written to logs. The only log line on the error path is a generic
  message with no content.
- The backend touches Supabase solely for **auth + paid status**, never for
  storing activity, calendar, or coaching data.

## Architecture

Single Lambda behind a **Function URL**. One `handler` dispatches on
method + path (Function URL payload format v2):

```
src/
  handler.ts            Function URL router: method + path → route handler
  routes/
    infer.ts            POST /v1/infer
    accountStatus.ts    GET  /v1/account/status
    stripeWebhook.ts    POST /v1/stripe/webhook
  lib/
    config.ts           env-var config (lazy getters)
    http.ts             JSON responses + typed HttpError hierarchy
    auth.ts             JWT verify + AUTH_DISABLED escape hatch
    supabase.ts         JWT verify + profiles read/write (service key)
    bedrock.ts          Bedrock Converse call + role mapping
    stripe.ts           webhook signature verification
test/                   vitest (all external services mocked)
supabase/profiles.sql   profiles table + trigger + RLS policies
```

## Endpoints

All inference/account routes require an `Authorization: Bearer <supabase-jwt>`
header. The webhook is authenticated by Stripe signature instead.

### `POST /v1/infer`

Verify JWT → check paid → forward to Bedrock Converse → return the completion.

Request:

```jsonc
{
  "model": "eu.anthropic.claude-sonnet-4-6", // optional; defaults to BEDROCK_MODEL_ID
  "messages": [
    { "role": "system", "content": "You are Bogi." },
    { "role": "user", "content": "Was I on task this afternoon?" }
  ],
  "max_tokens": 1024
}
```

`role` is one of `system | user | assistant`. `system` messages are mapped to
Bedrock Converse top-level system blocks; the rest become conversation turns.

Response: `200 { "text": "..." }`

Errors:

| Status | When                                            |
| ------ | ----------------------------------------------- |
| 400    | Missing/invalid body or `messages`              |
| 401    | Missing or invalid JWT                           |
| 402    | Authenticated but no active subscription         |
| 500    | Unexpected error (no content leaked)             |

### `GET /v1/account/status`

Verify JWT → return the authed user's entitlement.

Response: `200 { "paid": boolean, "plan": string | null }`

Errors: `401` when the JWT is missing/invalid.

### `POST /v1/stripe/webhook`

Verify the `stripe-signature` header against the raw body using
`STRIPE_WEBHOOK_SECRET`, then update Supabase. **Idempotent** — re-delivered
events re-apply the same state.

Handled events:

- `checkout.session.completed` → `paid = true` (uses `client_reference_id`, i.e.
  the Supabase user id set by the website checkout; stores `stripe_customer_id`
  and `plan` from metadata).
- `customer.subscription.created` / `customer.subscription.updated` → `paid` set
  from the subscription status (`active`/`trialing`/`past_due` count as paid),
  matched by `stripe_customer_id`.
- `customer.subscription.deleted` → `paid = false`.

Response: `200 { "received": true }` (also `200` for ignored event types so
Stripe stops retrying). `401` on a bad/missing signature.

## Environment variables

| Variable                | Required | Default                          | Purpose                                                        |
| ----------------------- | -------- | -------------------------------- | -------------------------------------------------------------- |
| `BEDROCK_REGION`        | no       | `eu-central-1`                   | AWS region hosting the Bedrock model                           |
| `BEDROCK_MODEL_ID`      | no       | `eu.anthropic.claude-sonnet-4-6` | Default Bedrock model id when a request omits `model`          |
| `SUPABASE_URL`          | yes\*    | —                                | Supabase project URL                                           |
| `SUPABASE_ANON_KEY`     | yes\*    | —                                | Anon key — used only to verify a caller's JWT                  |
| `SUPABASE_SERVICE_KEY`  | yes\*    | —                                | Service-role key — reads/writes `profiles` (bypasses RLS)      |
| `STRIPE_WEBHOOK_SECRET` | yes\*    | —                                | Verifies Stripe webhook signatures                             |
| `STRIPE_SECRET_KEY`     | no       | unused placeholder               | Not needed for webhook verification; reserved for future API   |
| `AUTH_DISABLED`         | no       | _off_                            | `1`/`true` skips JWT + paid checks for **local dev only**      |

\* Required only when the relevant route actually runs (config is read lazily),
and not required in tests because all external services are mocked.

No secrets are committed to the repo — everything is read from the environment.

## Local development

```bash
cd backend
npm install
npm run typecheck   # tsc --noEmit
npm run build       # esbuild bundle → dist/handler.mjs
npm test            # vitest run (all externals mocked; no network/credentials)
```

To run route logic without Supabase/Stripe credentials, set `AUTH_DISABLED=1`
(this bypasses JWT and paid checks — never enable it in production). Bedrock
calls still require valid AWS credentials in the environment.

## Deploy (Lambda + Function URL)

1. Build the bundle:

   ```bash
   npm run build   # produces dist/handler.mjs
   ```

2. Create a Node.js 22 Lambda with handler `handler.handler`, packaging
   `dist/handler.mjs` (the AWS SDK v3 is provided by the runtime and is kept
   external in the bundle).
3. Configure the environment variables above.
4. Grant the function's role `bedrock:InvokeModel` (Converse) on the target
   model in `BEDROCK_REGION`.
5. Enable a **Function URL** (auth type `NONE`; the app authenticates via the
   Supabase JWT, and the webhook via the Stripe signature).
6. Point the Stripe webhook endpoint at `<function-url>/v1/stripe/webhook` and
   set `STRIPE_WEBHOOK_SECRET` to that endpoint's signing secret.

## Supabase schema

Apply [`supabase/profiles.sql`](./supabase/profiles.sql) (via the SQL editor or
`supabase db push`). It creates `public.profiles`, a trigger that provisions a
row on new `auth.users`, and RLS policies so users can read only their own row
while writes are restricted to the service role.
