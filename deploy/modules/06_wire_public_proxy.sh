#!/bin/bash
set -euo pipefail

echo "📁 Step 6: Wiring /public/{proxy+} route..."

# Ensure REST_API_ID is set
if [ -z "${REST_API_ID:-}" ]; then
  echo "❌ REST_API_ID is not set."
  exit 1
fi

# Get or set PARENT_ID (root resource)
if [ -z "${PARENT_ID:-}" ]; then
  PARENT_ID=$(aws apigateway get-resources \
    --rest-api-id "$REST_API_ID" \
    --query 'items[0].id' \
    --output text)
  export PARENT_ID
fi

# Get or create /public base resource
PUBLIC_ID=$(aws apigateway get-resources \
  --rest-api-id "$REST_API_ID" \
  --query "items[?path=='/public'].id" \
  --output text)

if [ -z "$PUBLIC_ID" ]; then
  echo "🆕 Creating /public base resource..."
  PUBLIC_ID=$(aws apigateway create-resource \
    --rest-api-id "$REST_API_ID" \
    --parent-id "$PARENT_ID" \
    --path-part "public" \
    --query 'id' --output text)
fi

# Get or create /public/{proxy+}
PUBLIC_PROXY_ID=$(aws apigateway get-resources \
  --rest-api-id "$REST_API_ID" \
  --query "items[?path=='/public/{proxy+}'].id" \
  --output text)

if [ -z "$PUBLIC_PROXY_ID" ]; then
  echo "🆕 Creating /public/{proxy+} resource..."
  PUBLIC_PROXY_ID=$(aws apigateway create-resource \
    --rest-api-id "$REST_API_ID" \
    --parent-id "$PUBLIC_ID" \
    --path-part "{proxy+}" \
    --query 'id' --output text)
else
  echo "✅ /public/{proxy+} already exists."
fi

# Attach ANY method
aws apigateway put-method \
  --rest-api-id "$REST_API_ID" \
  --resource-id "$PUBLIC_PROXY_ID" \
  --http-method ANY \
  --authorization-type "NONE" || true

# Set Lambda proxy integration
aws apigateway put-integration \
  --rest-api-id "$REST_API_ID" \
  --resource-id "$PUBLIC_PROXY_ID" \
  --http-method ANY \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:$(aws sts get-caller-identity --query Account --output text):function:$LAMBDA_NAME/invocations || true

# Grant invoke permissions
aws lambda add-permission \
  --function-name "$LAMBDA_NAME" \
  --statement-id "publicproxy-$(date +%s)" \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn arn:aws:execute-api:us-east-1:$(aws sts get-caller-identity --query Account --output text):$REST_API_ID/*/*/public/* || true

echo "✅ Wired /public/{proxy+} route successfully."
