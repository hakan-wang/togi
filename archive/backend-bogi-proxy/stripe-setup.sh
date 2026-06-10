#!/usr/bin/env bash
# Creates the Togi Pro product + monthly/annual prices in Stripe, then prints the price IDs
# to drop into the Lambda env. Idempotent-ish: re-running creates NEW prices, so run once.
#
#   1. Authenticate the Stripe CLI first:  stripe login        (test mode)
#      For LIVE keys instead, export:      STRIPE_API_KEY=sk_live_...  and set LIVE=1
#   2. Run:                                ./stripe-setup.sh
#   3. Copy STRIPE_PRICE_MONTHLY / STRIPE_PRICE_ANNUAL into the deploy env, re-run deploy.sh
set -euo pipefail

ARGS=()
[ "${LIVE:-0}" = "1" ] && ARGS+=(--live)
[ -n "${STRIPE_API_KEY:-}" ] && ARGS+=(--api-key "$STRIPE_API_KEY")

id_from() { grep -oE "\"id\": \"$1[a-zA-Z0-9_]+\"" | head -1 | sed -E "s/.*\"($1[a-zA-Z0-9_]+)\".*/\1/"; }

echo "== creating product: Togi Pro =="
PRODUCT_ID=$(stripe products create "${ARGS[@]}" \
  --name "Togi Pro" \
  --description "Your always-on focus companion. Unlimited AI nudges, automatic day replanning, and coaching that learns your rhythm." \
  -d "metadata[app]=togi" | id_from "prod_")
echo "   PRODUCT_ID=$PRODUCT_ID"

echo "== creating monthly price: \$9.99/mo =="
PRICE_MONTHLY=$(stripe prices create "${ARGS[@]}" \
  --product "$PRODUCT_ID" --currency usd --unit-amount 999 \
  -d "recurring[interval]=month" --nickname "Togi Pro Monthly" | id_from "price_")
echo "   STRIPE_PRICE_MONTHLY=$PRICE_MONTHLY"

echo "== creating annual price: \$79/yr =="
PRICE_ANNUAL=$(stripe prices create "${ARGS[@]}" \
  --product "$PRODUCT_ID" --currency usd --unit-amount 7900 \
  -d "recurring[interval]=year" --nickname "Togi Pro Annual" | id_from "price_")
echo "   STRIPE_PRICE_ANNUAL=$PRICE_ANNUAL"

cat <<EOF

Done. Set these on the Lambda env and re-run deploy.sh:

  STRIPE_PRICE_MONTHLY=$PRICE_MONTHLY
  STRIPE_PRICE_ANNUAL=$PRICE_ANNUAL

Still to do in the Stripe dashboard (one-time):
  - Enable the Customer Portal: https://dashboard.stripe.com/settings/billing/portal
    (allow cancellation; let customers switch monthly <-> annual)
  - Add the webhook endpoint -> https://<your-api>/v1/stripe/webhook
    events: checkout.session.completed, customer.subscription.updated,
            customer.subscription.deleted, invoice.paid
    then copy the signing secret into STRIPE_WEBHOOK_SECRET.
EOF
