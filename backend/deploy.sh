#!/usr/bin/env bash
# Idempotent deploy of the Bogi backend Lambda + Function URL.
set -euo pipefail

PROFILE="${AWS_PROFILE:-er-fo-CLI}"
REGION="${BOGI_REGION:-eu-west-1}"
FN="bogi-backend"
ROLE="bogi-backend-role"
ACCOUNT="$(aws --profile "$PROFILE" sts get-caller-identity --query Account --output text)"
ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/${ROLE}"
AWS="aws --profile $PROFILE --region $REGION"

cd "$(dirname "$0")"

echo "== build =="
npm install --silent --no-fund --no-audit
npm run build --silent
( cd dist && zip -q -r ../function.zip handler.mjs )

echo "== iam role =="
if ! aws --profile "$PROFILE" iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws --profile "$PROFILE" iam create-role --role-name "$ROLE" \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws --profile "$PROFILE" iam attach-role-policy --role-name "$ROLE" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole >/dev/null
  aws --profile "$PROFILE" iam put-role-policy --role-name "$ROLE" --policy-name bedrock-invoke \
    --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["bedrock:InvokeModel","bedrock:InvokeModelWithResponseStream","bedrock:Converse","bedrock:ConverseStream"],"Resource":"*"}]}' >/dev/null
  echo "   created $ROLE; waiting for propagation"; sleep 12
fi

# Build environment as JSON (only include non-empty optional secrets).
node -e '
const v = { BEDROCK_REGION: process.env.REGION, BEDROCK_MODEL_ID: "eu.anthropic.claude-sonnet-4-6", AUTH_DISABLED: process.env.AUTH_DISABLED || "1" };
for (const k of ["SUPABASE_URL","SUPABASE_ANON_KEY","SUPABASE_SERVICE_KEY","STRIPE_WEBHOOK_SECRET"]) if (process.env[k]) v[k] = process.env[k];
require("fs").writeFileSync("env.json", JSON.stringify({ Variables: v }));
' REGION="$REGION"
ENV="file://env.json"

echo "== lambda =="
if $AWS lambda get-function --function-name "$FN" >/dev/null 2>&1; then
  $AWS lambda update-function-code --function-name "$FN" --zip-file fileb://function.zip >/dev/null
  $AWS lambda wait function-updated --function-name "$FN"
  $AWS lambda update-function-configuration --function-name "$FN" \
    --runtime nodejs22.x --handler handler.handler --timeout 30 --memory-size 512 --environment "$ENV" >/dev/null
else
  for i in 1 2 3 4 5; do
    if $AWS lambda create-function --function-name "$FN" --runtime nodejs22.x \
        --role "$ROLE_ARN" --handler handler.handler --timeout 30 --memory-size 512 \
        --environment "$ENV" --zip-file fileb://function.zip >/dev/null 2>/tmp/bogi_lambda_err; then break; fi
    echo "   create attempt $i failed (role propagation?), retrying"; sleep 8
  done
fi
$AWS lambda wait function-updated --function-name "$FN"

echo "== function url =="
if ! $AWS lambda get-function-url-config --function-name "$FN" >/dev/null 2>&1; then
  $AWS lambda create-function-url-config --function-name "$FN" --auth-type NONE >/dev/null
  $AWS lambda add-permission --function-name "$FN" --statement-id public-url \
    --action lambda:InvokeFunctionUrl --principal "*" --function-url-auth-type NONE >/dev/null 2>&1 || true
fi
URL="$($AWS lambda get-function-url-config --function-name "$FN" --query FunctionUrl --output text)"
echo "FUNCTION_URL=$URL"
