# Bogi backend

Stateless proxy. Holds the Bedrock-invoking IAM role, the Supabase service key, and the
Stripe secret. **Stores no user data** — the memory bank lives on the Mac.

## Endpoints
- `GET  /healthz` — Bedrock connectivity ping (no auth).
- `POST /v1/infer` — `{system?, messages:[{role,content}], maxTokens}` → `{text, usage}`.
  Auth: `X-Bogi-Authorization: Bearer <supabase access token>` (paid users only).
- `GET  /v1/account/status` — `{paid, plan}` for the authed user.
- `POST /v1/stripe/webhook` — flips `profiles.paid` on Stripe events (HMAC-verified).

## Inference
AWS Bedrock, model `eu.anthropic.claude-sonnet-4-6` (EU inference profile; the bare
`anthropic.claude-sonnet-4-6` is rejected for on-demand), region `eu-west-1`.

## Exposure — API Gateway, NOT Function URL
The account's org SCP denies `lambda:InvokeFunctionUrl`, so Lambda Function URLs (public
or CloudFront-OAC/AWS_IAM) 403 at the edge. We expose via **API Gateway HTTP API**
(`lambda:InvokeFunction`), which the SCP allows.

## Deploy
```sh
AWS_PROFILE=er-fo-CLI ./deploy.sh   # build + deploy the Lambda
AWS_PROFILE=er-fo-CLI ./apigw.sh    # ensure the API Gateway in front; prints BACKEND_BASE_URL
```
Current: `https://e7fsq18rqf.execute-api.eu-west-1.amazonaws.com`

## Pending (gated)
- **Supabase**: apply `supabase/profiles.sql` (needs a Supabase access token `sbp_…` or DB
  password), then set `SUPABASE_URL`/`SUPABASE_ANON_KEY`/`SUPABASE_SERVICE_KEY` on the
  Lambda and flip `AUTH_DISABLED=0`.
- **Stripe**: set `STRIPE_WEBHOOK_SECRET`, register the webhook → `/v1/stripe/webhook`.
