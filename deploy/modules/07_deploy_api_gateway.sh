#!/bin/bash
set -euo pipefail

echo "🚀 Step 7: Deploying API Gateway..."

aws apigateway create-deployment \
  --rest-api-id "$REST_API_ID" \
  --stage-name prod

echo "🌎 API URL: https://${REST_API_ID}.execute-api.us-east-1.amazonaws.com/prod"
