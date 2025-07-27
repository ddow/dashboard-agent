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
  # Get the Lambda ARN
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region us-east-1)
  LAMBDA_ARN="arn:aws:lambda:us-east-1:${ACCOUNT_ID}:function:${LAMBDA_NAME}"
  INVOCATION_ARN="arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations"

  # Query existing APIs to find one integrated with this Lambda
  REST_API_ID=$(aws apigateway get-rest-apis \
    --query "items[].[id, name, endpointConfiguration.types, disableExecuteApiEndpoint, createdDate]" \
    --output text \
    --region us-east-1 | while read -r id name types disabled date; do
      if [ "$disabled" != "true" ] && [ "${types}" = "[EDGE]" ]; then
        # Check integrations for this API
        resources=$(aws apigateway get-resources --rest-api-id "$id" --query "items[].id" --output text --region us-east-1)
        for resource in $resources; do
          integration=$(aws apigateway get-integration --rest-api-id "$id" --resource-id "$resource" --http-method POST --region us-east-1 2>/dev/null)
          if [ -n "$integration" ] && echo "$integration" | grep -q "$INVOCATION_ARN"; then
            echo "$id"
            break 2
          fi
        done
      fi
    done | head -n 1)
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