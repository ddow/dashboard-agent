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
echo "🌐 Step 4: Setting up API Gateway for Lambda: $LAMBDA_NAME"

if [ "${DRY_RUN:-false}" = "true" ]; then
  echo "🧪 DRY RUN: Skipping: aws lambda get-function and API Gateway checks"
  REST_API_ID=""
else
  # Look up existing API Gateway by name
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region us-east-1)
  INVOCATION_ARN="arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:${ACCOUNT_ID}:function:${LAMBDA_NAME}/invocations"

  REST_API_ID=$(aws apigateway get-rest-apis \
    --query "items[?name=='${API_NAME}'].id | [0]" \
    --output text \
    --region us-east-1)

  # Normalize "None" (no match) to empty string
  if [ "$REST_API_ID" = "None" ]; then
    REST_API_ID=""
  fi
fi
export REST_API_ID

if [ -z "$REST_API_ID" ] || [ "$REST_API_ID" = "None" ]; then
  if [ "${DRY_RUN:-false}" = "true" ]; then
    echo "🧪 DRY RUN: Skipping: aws apigateway create-rest-api"
  else
    # Create a new API with EDGE configuration
    REST_API_ID=$(aws apigateway create-rest-api \
      --name "$API_NAME" \
      --endpoint-configuration types=EDGE \
      --query 'id' \
      --output text \
      --region us-east-1)
    echo "🆕 Created new API Gateway: $REST_API_ID"

    # Get root resource ID for the new API
    PARENT_ID=$(aws apigateway get-resources --rest-api-id "$REST_API_ID" --query 'items[0].id' --output text --region us-east-1)

    # Wire the integration to this Lambda
    aws apigateway create-resource --rest-api-id "$REST_API_ID" --parent-id "$PARENT_ID" --path-part "login" --region us-east-1
    LOGIN_RESOURCE_ID=$(aws apigateway get-resources --rest-api-id "$REST_API_ID" --query "items[?path=='/login'].id" --output text --region us-east-1)
    aws apigateway put-method --rest-api-id "$REST_API_ID" --resource-id "$LOGIN_RESOURCE_ID" --http-method POST --authorization-type "NONE" --region us-east-1
    aws apigateway put-integration --rest-api-id "$REST_API_ID" --resource-id "$LOGIN_RESOURCE_ID" --http-method POST --type AWS_PROXY --integration-http-method POST --uri "$INVOCATION_ARN" --region us-east-1
    aws lambda add-permission --function-name "$LAMBDA_NAME" --statement-id "apigw-login-$(date +%s)" --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn "arn:aws:execute-api:us-east-1:${ACCOUNT_ID}:$REST_API_ID/*/*/*" --region us-east-1
  fi
  echo "🆕 Wired new API Gateway to Lambda: $LAMBDA_NAME"
else
  echo "✅ Using existing API Gateway linked to Lambda: $REST_API_ID"
  # Get or set PARENT_ID for the existing API
  if [ "${DRY_RUN:-false}" = "true" ]; then
    echo "🧪 DRY RUN: Skipping: aws apigateway get-resources --rest-api-id $REST_API_ID --query items[0].id --output text"
    PARENT_ID=""
  else
    PARENT_ID=$(aws apigateway get-resources --rest-api-id "$REST_API_ID" --query 'items[0].id' --output text --region us-east-1)
  fi
fi
export PARENT_ID