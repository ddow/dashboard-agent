#!/bin/bash
set -euo pipefail

# Allow skipping AWS calls when DRY_RUN=true
DRY_RUN=${DRY_RUN:-false}

echo "🚀 Step 7: Deploying API Gateway..."

if [ "${DRY_RUN:-false}" = "true" ]; then
  echo "🧪 DRY RUN: Skipping: aws apigateway create-deployment --rest-api-id $REST_API_ID --stage-name prod"
else
  aws apigateway create-deployment \
    --rest-api-id "$REST_API_ID" \
    --stage-name prod
fi

echo "🌎 API URL: https://${REST_API_ID}.execute-api.us-east-1.amazonaws.com/prod"
