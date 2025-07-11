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
echo "🌐 Step 4: Setting up API Gateway: $API_NAME"

if [ "${DRY_RUN:-false}" = "true" ]; then
  echo "🧪 DRY RUN: Skipping: aws apigateway get-rest-apis --query items[?name=='$API_NAME'].id --output text"
  REST_API_ID=""
else
  REST_API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text)
fi
export REST_API_ID

if [ -z "$REST_API_ID" ]; then
  if [ "${DRY_RUN:-false}" = "true" ]; then
    echo "🧪 DRY RUN: Skipping: aws apigateway create-rest-api --name $API_NAME"
  else
    REST_API_ID=$(aws apigateway create-rest-api --name "$API_NAME" --query 'id' --output text)
  fi
  echo "🆕 Created API Gateway: $REST_API_ID"
else
  echo "✅ API Gateway already exists: $REST_API_ID"
fi

if [ "${DRY_RUN:-false}" = "true" ]; then
  echo "🧪 DRY RUN: Skipping: aws apigateway get-resources --rest-api-id $REST_API_ID --query items[0].id --output text"
  PARENT_ID=""
else
  PARENT_ID=$(aws apigateway get-resources --rest-api-id "$REST_API_ID" --query 'items[0].id' --output text)
fi
export PARENT_ID
