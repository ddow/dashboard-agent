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

# Use REST_API_ID from 04_setup_api_gateway.sh first
if [ -z "${REST_API_ID:-}" ]; then
  echo "🔧 REST_API_ID not set from previous step, attempting to fetch latest API..."
  if [ "$DRY_RUN" = "false" ]; then
    # Try to get REST_API_ID from CloudFormation, but validate it
    REST_API_ID=$(aws cloudformation describe-stacks \
      --stack-name dashboard-prod \
      --region us-east-1 \
      --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" \
      --output text | awk -F'[./]' '{print $3}' 2>/dev/null || true)
    if [ -n "$REST_API_ID" ] && [ "$REST_API_ID" != "None" ]; then
      # Verify the API exists
      if ! aws apigateway get-rest-api --rest-api-id "$REST_API_ID" --region us-east-1 >/dev/null 2>&1; then
        echo "⚠️ Invalid or deleted REST_API_ID from CloudFormation: $REST_API_ID. Fetching latest API..."
        REST_API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME']|[0].id" --output text --region us-east-1)
      fi
    else
      echo "⚠️ No valid REST_API_ID from CloudFormation. Fetching latest API..."
      REST_API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME']|[0].id" --output text --region us-east-1)
    fi
    if [ -z "$REST_API_ID" ] || [ "$REST_API_ID" = "None" ]; then
      echo "❌ No recent API Gateway found. Check 04_setup_api_gateway.sh output."
      exit 1
    fi
    echo "🔧 REST_API_ID auto-detected: $REST_API_ID"
    export REST_API_ID
  else
    echo "🧪 DRY RUN: Faking REST_API_ID"
    REST_API_ID="dryrun-api-id"
    export REST_API_ID
  fi
else
  echo "🔧 Using REST_API_ID from previous step: $REST_API_ID"
fi

# Deploy the API Gateway
if [ "$DRY_RUN" = "true" ]; then
  echo "🧪 DRY RUN: Skipping: aws apigateway create-deployment"
else
  DEPLOYMENT_ID=$(aws apigateway create-deployment \
    --rest-api-id "$REST_API_ID" \
    --stage-name "prod" \
    --region us-east-1 \
    --query "id" --output text)
  echo "{ \"id\": \"$DEPLOYMENT_ID\", \"createdDate\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" }"
  echo "🌎 API URL: https://${REST_API_ID}.execute-api.us-east-1.amazonaws.com/prod"
fi

echo "✅ API Gateway deployed."