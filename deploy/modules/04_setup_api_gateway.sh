#!/bin/bash
set -euo pipefail

echo "🌐 Step 4: Setting up API Gateway: $API_NAME"

REST_API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text)
export REST_API_ID

if [ -z "$REST_API_ID" ]; then
  REST_API_ID=$(aws apigateway create-rest-api --name "$API_NAME" --query 'id' --output text)
  echo "🆕 Created API Gateway: $REST_API_ID"
else
  echo "✅ API Gateway already exists: $REST_API_ID"
fi

export PARENT_ID=$(aws apigateway get-resources --rest-api-id "$REST_API_ID" --query 'items[0].id' --output text)
