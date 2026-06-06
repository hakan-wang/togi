#!/usr/bin/env bash
# Put CloudFront (public, allowed) in front of the Lambda Function URL using OAC + AWS_IAM,
# so we avoid the org guardrail on public Function URLs. Idempotent-ish.
set -euo pipefail
PROFILE="${AWS_PROFILE:-er-fo-CLI}"
REGION="eu-west-1"
FN="bogi-backend"
P="aws --profile $PROFILE"

FN_ARN="$($P --region $REGION lambda get-function --function-name $FN --query 'Configuration.FunctionArn' --output text)"
URL="$($P --region $REGION lambda get-function-url-config --function-name $FN --query FunctionUrl --output text)"
ORIGIN_DOMAIN="$(echo "$URL" | sed -E 's#https?://([^/]+)/?#\1#')"
echo "origin domain: $ORIGIN_DOMAIN"

echo "== switch Function URL to AWS_IAM =="
$P --region $REGION lambda update-function-url-config --function-name $FN --auth-type AWS_IAM >/dev/null
$P --region $REGION lambda remove-permission --function-name $FN --statement-id public-url >/dev/null 2>&1 || true

echo "== origin access control (lambda) =="
OAC_ID="$($P cloudfront list-origin-access-controls --query "OriginAccessControlList.Items[?Name=='bogi-oac'].Id | [0]" --output text 2>/dev/null || echo None)"
if [ "$OAC_ID" = "None" ] || [ -z "$OAC_ID" ]; then
  OAC_ID="$($P cloudfront create-origin-access-control --origin-access-control-config \
    "Name=bogi-oac,Description=Bogi Lambda OAC,SigningProtocol=sigv4,SigningBehavior=always,OriginAccessControlOriginType=lambda" \
    --query 'OriginAccessControl.Id' --output text)"
fi
echo "OAC: $OAC_ID"

echo "== distribution =="
DIST_ID="$($P cloudfront list-distributions --query "DistributionList.Items[?Comment=='bogi-backend'].Id | [0]" --output text 2>/dev/null || echo None)"
if [ "$DIST_ID" = "None" ] || [ -z "$DIST_ID" ]; then
  ORIGIN_DOMAIN="$ORIGIN_DOMAIN" OAC_ID="$OAC_ID" node -e '
  const o=process.env.ORIGIN_DOMAIN, oac=process.env.OAC_ID;
  const cfg={
    CallerReference:"bogi-backend-"+o,
    Comment:"bogi-backend", Enabled:true,
    Origins:{Quantity:1,Items:[{Id:"lambda",DomainName:o,OriginAccessControlId:oac,
      CustomOriginConfig:{HTTPPort:80,HTTPSPort:443,OriginProtocolPolicy:"https-only",
        OriginSslProtocols:{Quantity:1,Items:["TLSv1.2"]},OriginReadTimeout:60,OriginKeepaliveTimeout:5},
      CustomHeaders:{Quantity:0,Items:[]},OriginShield:{Enabled:false}}]},
    DefaultCacheBehavior:{TargetOriginId:"lambda",ViewerProtocolPolicy:"https-only",
      AllowedMethods:{Quantity:7,Items:["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"],
        CachedMethods:{Quantity:2,Items:["GET","HEAD"]}},
      Compress:false,
      CachePolicyId:"4135ea2d-6df8-44a3-9df3-4b5a84be39ad",            /* Managed-CachingDisabled */
      OriginRequestPolicyId:"b689b0a8-53d0-40ab-baf2-68738e2966ac"},   /* Managed-AllViewerExceptHostHeader */
    PriceClass:"PriceClass_100"
  };
  require("fs").writeFileSync("dist-config.json",JSON.stringify({DistributionConfig:cfg}));
  '
  OUT="$($P cloudfront create-distribution --cli-input-json file://dist-config.json)"
  DIST_ID="$(echo "$OUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).Distribution.Id))')"
fi
DIST_ARN="$($P cloudfront get-distribution --id "$DIST_ID" --query 'Distribution.ARN' --output text)"
DOMAIN="$($P cloudfront get-distribution --id "$DIST_ID" --query 'Distribution.DomainName' --output text)"
echo "DIST_ID=$DIST_ID"

echo "== allow CloudFront to invoke the Function URL =="
$P --region $REGION lambda add-permission --function-name $FN --statement-id cloudfront-oac \
  --action lambda:InvokeFunctionUrl --principal cloudfront.amazonaws.com \
  --source-arn "$DIST_ARN" --function-url-auth-type AWS_IAM >/dev/null 2>&1 || true

echo "CLOUDFRONT_DOMAIN=https://$DOMAIN"
