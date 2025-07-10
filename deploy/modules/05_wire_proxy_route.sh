#!/bin/bash
set -euo pipefail

# Allow skipping AWS calls when DRY_RUN=true
DRY_RUN=${DRY_RUN:-false}

echo "🔗 Step 5: Wiring {proxy+} route..."

# Ensure REST_API_ID is set
if [ -z "${REST_API_ID:-}" ]; then
  echo "❌ REST_API_ID is not set."
  exit 1
fi

# Get or set PARENT_ID (root resource)
if [ -z "${PARENT_ID:-}" ]; then
  if [ "${DRY_RUN:-false}" = "true" ]; then
    echo "🧪 DRY RUN: Skipping: aws apigateway get-resources --rest-api-id $REST_API_ID --query items[0].id --output text"
    PARENT_ID=""
  else
    PARENT_ID=$(aws apigateway get-resources \
      --rest-api-id "$REST_API_ID" \
      --query 'items[0].id' \
      --output text)
  fi
  export PARENT_ID
fi

if [ "${DRY_RUN:-false}" = "true" ]; then
  echo "🧪 DRY RUN: Skipping: aws apigateway create-resource --rest-api-id $REST_API_ID --parent-id $PARENT_ID --path-part {proxy+}"
  RESOURCE_ID=""
else
  RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id "$REST_API_ID" \
    --parent-id "$PARENT_ID" \
    --path-part "{proxy+}" \
    --query 'id' --output text 2>/dev/null || true)
fi

if [ -z "$RESOURCE_ID" ]; then
  echo "⚠️ {proxy+} already exists. Fetching existing resource ID..."
  if [ "${DRY_RUN:-false}" = "true" ]; then
    echo "🧪 DRY RUN: Skipping: aws apigateway get-resources --rest-api-id $REST_API_ID --query items[?pathPart=='{proxy+}'].id | [0] --output text"
    RESOURCE_ID=""
  else
    RESOURCE_ID=$(aws apigateway get-resources \
      --rest-api-id "$REST_API_ID" \
      --query "items[?pathPart=='{proxy+}'].id | [0]" \
      --output text)
  fi
fi

if [ -z "$RESOURCE_ID" ]; then
  echo "❌ Failed to create or fetch {proxy+} resource. Exiting."
  exit 1
fi

# Attach method and integration
if [ "${DRY_RUN:-false}" = "true" ]; then
  echo "🧪 DRY RUN: Skipping: aws apigateway put-method --rest-api-id $REST_API_ID --resource-id $RESOURCE_ID"
else
  aws apigateway put-method \
    --rest-api-id "$REST_API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method ANY \
    --authorization-type "NONE" || true
fi

if [ "${DRY_RUN:-false}" = "true" ]; then
  echo "🧪 DRY RUN: Skipping: aws apigateway put-integration --rest-api-id $REST_API_ID --resource-id $RESOURCE_ID"
else
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  aws apigateway put-integration \
    --rest-api-id "$REST_API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method ANY \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:${ACCOUNT_ID}:function:$LAMBDA_NAME/invocations || true
fi

if [ "${DRY_RUN:-false}" = "true" ]; then
  echo "🧪 DRY RUN: Skipping: aws lambda add-permission --function-name $LAMBDA_NAME"
else
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  aws lambda add-permission \
    --function-name "$LAMBDA_NAME" \
    --statement-id "proxy-$(date +%s)" \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn arn:aws:execute-api:us-east-1:${ACCOUNT_ID}:$REST_API_ID/*/*/* || true
fi

echo "✅ Wired {proxy+} route successfully."
