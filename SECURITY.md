# Security — secrets & API keys

How secrets flow through Togi, what is intentionally public, and what is actually secret.
Read this before rotating anything or reporting a "leaked key."

## TL;DR

- **There is no LLM API key.** Inference goes Mac → API Gateway → Lambda → **AWS Bedrock
  via an IAM role** (`backend/deploy.sh` `bedrock-invoke` policy). Nothing to leak.
- **Real secrets live only as Lambda env vars**, injected at deploy from a gitignored file.
  They are never in the repo and never in the Mac app.
- **Two values committed in the client are public by design** — do not panic-rotate them.

## Public by design — NOT leaks

These ship in the client/repo on purpose. The security boundary is something else, not the
value's secrecy.

| Value | Where | Why it's safe to expose |
|---|---|---|
| Supabase **anon key** | `apps/macos/Bogi/Sources/BogiApp/Infrastructure/AI/BackendConfig.swift` (`SupabaseConfig.anonKey`) | Anon keys are publishable; the boundary is **Row-Level Security**, not the key. |
| Google **Desktop OAuth client secret** | same file (`GoogleConfig.clientSecret`) | For a **Desktop** OAuth client this is non-confidential per RFC 8252; **PKCE** is the boundary. Tokens live in the macOS Keychain. |

> ⚠️ The Google value is only non-confidential because the client is a **Desktop** type. If
> it is ever recreated as a **Web** client, the secret becomes confidential and must move
> server-side.

## Actually secret — never commit, never ship to the client

| Secret | Lives where |
|---|---|
| Supabase **service-role key** | Lambda env var `SUPABASE_SERVICE_KEY` only |
| Stripe **secret key** | Lambda env var `STRIPE_SECRET_KEY` only |
| Stripe **webhook signing secret** | Lambda env var `STRIPE_WEBHOOK_SECRET` only |

These are injected at deploy from your shell into a **gitignored** `backend/env.json`
(see `backend/deploy.sh`, "Build environment as JSON"). `backend/env.json` is listed in
`.gitignore` and has never been committed. Keep it local and on an encrypted disk.

## How the paid endpoint is protected

The biggest real risk isn't a key — it's someone draining our **paid Bedrock access**
through the public Lambda Function URL (`--auth-type NONE`). Two safeguards:

1. **`/healthz` does not call Bedrock.** The default health check returns a static body.
   The Bedrock connectivity ping is opt-in via `?deep=1` **and requires a valid Supabase
   token** (`backend/src/handler.mjs`).
2. **`AUTH_DISABLED` can't open a real deploy.** The dev auth bypass is honored **only when
   no `SUPABASE_URL` is configured** (true local dev). If `AUTH_DISABLED=1` reaches a deploy
   that has `SUPABASE_URL` set, it is ignored, auth stays enforced, and the Lambda logs a
   loud warning (`handler.mjs`, `wsHandler.mjs`).

## Recommended next steps (not yet done)

- **Secret scanning:** add [`gitleaks`](https://github.com/gitleaks/gitleaks) as a local
  pre-commit hook and a CI job to block accidental secret commits.
- **Edge rate-limiting:** put an AWS WAF rate rule or API Gateway usage plan in front of the
  Function URL so even authenticated abuse is capped.
- **Move Lambda env secrets to SSM Parameter Store (SecureString)** so the service-role and
  Stripe keys aren't plaintext in the Lambda configuration (visible to anyone with
  `lambda:GetFunctionConfiguration`).

## Reporting

Found a real leak (a true secret in the repo/history, or an open endpoint)? Rotate the
affected secret first, then flag it. Do not rotate the public-by-design values above without
reading this file.
