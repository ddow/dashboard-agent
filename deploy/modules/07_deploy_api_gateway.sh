#!/bin/bash
# Default environment variables
BUILD_DIR=${BUILD_DIR:-dashboard-app/backend/lambda-build}
ZIP_FILE=${ZIP_FILE:-dashboard-app/backend/dashboard-backend.zip}
LAMBDA_NAME=${LAMBDA_NAME:-dashboard-backend}
ROLE_NAME=${ROLE_NAME:-DashboardLambdaRole}
POLICY_ARN=${POLICY_ARN:-arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess}
API_NAME=${API_NAME:-dashboard-api}

set -euo pipefail

# Allow skipping AWS calls when DRY_RUN=true
DRY_RUN=${DRY_RUN:-false}

echo "🚀 Step 7: Deploying API Gateway..."

# Ensure REST_API_ID is set (auto‑detect from CF if missing)
if [ -z "${REST_API_ID:-}" ]; then
  echo "🔧 REST_API_ID not set, fetching from CloudFormation…"
  if [ "$DRY_RUN" = "true" ]; then
    echo "🧪 DRY RUN: Skipping CloudFormation lookup"
    REST_API_ID="dryrun-api-id"
  else
    REST_API_ID=$(aws cloudformation describe-stacks \
      --stack-name dashboard-prod \
      --region us-east-1 \
      --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" \
      --output text | awk -F'[/.]' '{print $4}')
  fi
  echo "🔧 REST_API_ID auto‑detected: $REST_API_ID"
  export REST_API_ID
fi


if [ "${DRY_RUN:-false}" = "true" ]; then
  echo "🧪 DRY RUN: Skipping: aws apigateway create-deployment --rest-api-id $REST_API_ID --stage-name prod"
else
  aws apigateway create-deployment \
    --rest-api-id "$REST_API_ID" \
    --stage-name prod
fi

echo "🌎 API URL: https://${REST_API_ID}.execute-api.us-east-1.amazonaws.com/prod"
