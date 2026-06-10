#!/usr/bin/env bash
# Expose the Bogi WebSocket Lambda via API Gateway WebSocket API.
# Routes: $connect (authorize via ?token=), $disconnect (noop), infer (ConverseStream).
#
# WHY API Gateway and not a Lambda Function URL / CloudFront-OAC:
# this AWS account is in an Organization (o-ftgcxnenir) whose SCP denies
# `lambda:InvokeFunctionUrl` — so EVERY Function URL path (public NONE, or CloudFront
# OAC with AWS_IAM) returns 403 at the edge. API Gateway invokes via
# `lambda:InvokeFunction` (a different action the SCP allows), so it works.
#
# The Lambda execution role needs:
#   - bedrock:InvokeModelWithResponseStream (for ConverseStream)
#   - execute-api:ManageConnections on this WebSocket API (to push frames back)
# Example managed-connections policy statement to add to the role:
#   {"Effect":"Allow","Action":"execute-api:ManageConnections",
#    "Resource":"arn:aws:execute-api:<REGION>:<ACCOUNT>:<API_ID>/<STAGE>/*"}
set -euo pipefail
PROFILE="${AWS_PROFILE:-er-fo-CLI}"; REGION="eu-west-1"; FN="bogi-ws-backend"
ACCOUNT="$(aws --profile "$PROFILE" sts get-caller-identity --query Account --output text)"
LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT}:function:${FN}"
ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/bogi-lambda-role"
STAGE="prod"

# ── 1. Create or locate the Lambda ──────────────────────────────────────────
if ! aws --profile "$PROFILE" --region "$REGION" lambda get-function --function-name "$FN" >/dev/null 2>&1; then
  echo "Creating Lambda ${FN}..."
  # Build the deployment package if not already present.
  if [ ! -f dist/wsHandler.mjs ]; then
    npm run build:ws 2>/dev/null || \
      npx esbuild src/wsHandler.mjs --bundle --platform=node --target=node22 --format=esm \
        --outfile=dist/wsHandler.mjs \
        --banner:js="import{createRequire}from'module';const require=createRequire(import.meta.url);"
  fi
  cd dist && zip -q wsHandler.zip wsHandler.mjs && cd ..
  aws --profile "$PROFILE" --region "$REGION" lambda create-function \
    --function-name "$FN" \
    --runtime nodejs22.x \
    --role "$ROLE_ARN" \
    --handler wsHandler.handler \
    --zip-file fileb://dist/wsHandler.zip \
    --timeout 30 \
    --query FunctionArn --output text
else
  echo "Lambda ${FN} already exists — updating code..."
  if [ ! -f dist/wsHandler.mjs ]; then
    npm run build:ws 2>/dev/null || \
      npx esbuild src/wsHandler.mjs --bundle --platform=node --target=node22 --format=esm \
        --outfile=dist/wsHandler.mjs \
        --banner:js="import{createRequire}from'module';const require=createRequire(import.meta.url);"
  fi
  cd dist && zip -q wsHandler.zip wsHandler.mjs && cd ..
  aws --profile "$PROFILE" --region "$REGION" lambda update-function-code \
    --function-name "$FN" \
    --zip-file fileb://dist/wsHandler.zip \
    --query FunctionArn --output text
fi

# ── 2. Create or locate the WebSocket API ───────────────────────────────────
API_ID="$(aws --profile "$PROFILE" --region "$REGION" apigatewayv2 get-apis \
  --query "Items[?Name=='bogi-ws-api'].ApiId | [0]" --output text)"
if [ "$API_ID" = "None" ] || [ -z "$API_ID" ]; then
  echo "Creating WebSocket API bogi-ws-api..."
  API_ID="$(aws --profile "$PROFILE" --region "$REGION" apigatewayv2 create-api \
    --name bogi-ws-api \
    --protocol-type WEBSOCKET \
    --route-selection-expression '$request.body.action' \
    --query ApiId --output text)"
fi
echo "API_ID=${API_ID}"

# ── 3. Create Lambda integration ─────────────────────────────────────────────
INTEGRATION_ID="$(aws --profile "$PROFILE" --region "$REGION" apigatewayv2 get-integrations \
  --api-id "$API_ID" \
  --query "Items[?IntegrationUri=='${LAMBDA_ARN}'].IntegrationId | [0]" --output text 2>/dev/null || true)"
if [ "$INTEGRATION_ID" = "None" ] || [ -z "$INTEGRATION_ID" ]; then
  echo "Creating AWS_PROXY integration..."
  INTEGRATION_ID="$(aws --profile "$PROFILE" --region "$REGION" apigatewayv2 create-integration \
    --api-id "$API_ID" \
    --integration-type AWS_PROXY \
    --integration-uri "arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" \
    --content-handling-strategy CONVERT_TO_TEXT \
    --query IntegrationId --output text)"
fi
echo "INTEGRATION_ID=${INTEGRATION_ID}"
INTEGRATION_URI="integrations/${INTEGRATION_ID}"

# ── 4. Create routes ($connect, $disconnect, infer) ──────────────────────────
for ROUTE_KEY in "\$connect" "\$disconnect" "infer"; do
  ROUTE_ID="$(aws --profile "$PROFILE" --region "$REGION" apigatewayv2 get-routes \
    --api-id "$API_ID" \
    --query "Items[?RouteKey=='${ROUTE_KEY}'].RouteId | [0]" --output text 2>/dev/null || true)"
  if [ "$ROUTE_ID" = "None" ] || [ -z "$ROUTE_ID" ]; then
    echo "Creating route ${ROUTE_KEY}..."
    aws --profile "$PROFILE" --region "$REGION" apigatewayv2 create-route \
      --api-id "$API_ID" \
      --route-key "${ROUTE_KEY}" \
      --target "$INTEGRATION_URI" \
      --query RouteId --output text
  else
    echo "Route ${ROUTE_KEY} already exists (${ROUTE_ID})."
  fi
done

# ── 5. Deploy the stage ───────────────────────────────────────────────────────
DEPLOYMENT_ID="$(aws --profile "$PROFILE" --region "$REGION" apigatewayv2 create-deployment \
  --api-id "$API_ID" \
  --query DeploymentId --output text)"
aws --profile "$PROFILE" --region "$REGION" apigatewayv2 update-stage \
  --api-id "$API_ID" \
  --stage-name "$STAGE" \
  --deployment-id "$DEPLOYMENT_ID" >/dev/null 2>&1 || \
  aws --profile "$PROFILE" --region "$REGION" apigatewayv2 create-stage \
    --api-id "$API_ID" \
    --stage-name "$STAGE" \
    --deployment-id "$DEPLOYMENT_ID" >/dev/null

# ── 6. Grant API Gateway permission to invoke the Lambda ──────────────────────
aws --profile "$PROFILE" --region "$REGION" lambda add-permission \
  --function-name "$FN" \
  --statement-id apigw-ws-invoke \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT}:${API_ID}/*/*" >/dev/null 2>&1 || true

echo ""
echo "BOGI_WS_URL=wss://${API_ID}.execute-api.${REGION}.amazonaws.com/${STAGE}"
echo ""
echo "Remember to add execute-api:ManageConnections to the Lambda role policy:"
echo "  Resource: arn:aws:execute-api:${REGION}:${ACCOUNT}:${API_ID}/${STAGE}/*"
