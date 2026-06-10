#!/usr/bin/env bash
# Expose the Bogi Lambda via API Gateway HTTP API (payload format 2.0 → handler reads
# event.requestContext.http.method + event.rawPath directly).
#
# WHY API Gateway and not a Lambda Function URL / CloudFront-OAC:
# this AWS account is in an Organization (o-ftgcxnenir) whose SCP denies
# `lambda:InvokeFunctionUrl` — so EVERY Function URL path (public NONE, or CloudFront
# OAC with AWS_IAM) returns 403 at the edge. API Gateway invokes via
# `lambda:InvokeFunction` (a different action the SCP allows), so it works.
set -euo pipefail
PROFILE="${AWS_PROFILE:-er-fo-CLI}"; REGION="eu-west-1"; FN="bogi-backend"
ACCOUNT="$(aws --profile "$PROFILE" sts get-caller-identity --query Account --output text)"
LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT}:function:${FN}"

API_ID="$(aws --profile "$PROFILE" --region "$REGION" apigatewayv2 get-apis \
  --query "Items[?Name=='bogi-api'].ApiId | [0]" --output text)"
if [ "$API_ID" = "None" ] || [ -z "$API_ID" ]; then
  API_ID="$(aws --profile "$PROFILE" --region "$REGION" apigatewayv2 create-api \
    --name bogi-api --protocol-type HTTP --target "$LAMBDA_ARN" \
    --query ApiId --output text)"
fi

aws --profile "$PROFILE" --region "$REGION" lambda add-permission --function-name "$FN" \
  --statement-id apigw-invoke --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:${REGION}:${ACCOUNT}:${API_ID}/*/*" >/dev/null 2>&1 || true

echo "BACKEND_BASE_URL=https://${API_ID}.execute-api.${REGION}.amazonaws.com"
