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

if [ "$DRY_RUN" = "true" ]; then
  echo "🧪 DRY RUN: Would create API Gateway: $API_NAME"
  REST_API_ID="dryrun-api-id"
else
  # Create API Gateway with explicit name
  REST_API_ID=$(aws apigateway create-rest-api --name "$API_NAME" --endpoint-configuration types=REGIONAL --region us-east-1 --query id --output text)
  if [ -z "$REST_API_ID" ] || [ "$REST_API_ID" = "None" ]; then
    echo "❌ Failed to create API Gateway. Check permissions or AWS status."
    exit 1
  fi
  echo "🆕 Created new API Gateway: $REST_API_ID"

  # Create /login resource
  RESOURCE_ID=$(aws apigateway create-resource --rest-api-id "$REST_API_ID" --parent-id "$(aws apigateway get-resources --rest-api-id "$REST_API_ID" --query "items[0].id" --output text --region us-east-1)" --path-part "login" --query id --output text --region us-east-1)
  echo "{ \"id\": \"$RESOURCE_ID\", \"parentId\": \"$(aws apigateway get-resources --rest-api-id "$REST_API_ID" --query "items[0].id" --output text --region us-east-1)\", \"pathPart\": \"login\", \"path\": \"/login\" }"

  # Attach POST method
  aws apigateway put-method --rest-api-id "$REST_API_ID" --resource-id "$RESOURCE_ID" --http-method POST --authorization-type "NONE" --region us-east-1
  echo "{ \"httpMethod\": \"POST\", \"authorizationType\": \"NONE\", \"apiKeyRequired\": false }"

  # Set Lambda integration
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region us-east-1)
  aws apigateway put-integration --rest-api-id "$REST_API_ID" --resource-id "$RESOURCE_ID" --http-method POST --type AWS_PROXY --integration-http-method POST --uri "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:${ACCOUNT_ID}:function:$LAMBDA_NAME/invocations" --region us-east-1
  echo "{ \"type\": \"AWS_PROXY\", \"httpMethod\": \"POST\", \"uri\": \"arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:${ACCOUNT_ID}:function:$LAMBDA_NAME/invocations\", \"passthroughBehavior\": \"WHEN_NO_MATCH\", \"timeoutInMillis\": 29000, \"cacheNamespace\": \"$RESOURCE_ID\", \"cacheKeyParameters\": [] }"

  # Add Lambda permission
  aws lambda add-permission --function-name "$LAMBDA_NAME" --statement-id "apigw-login-$(date +%s)" --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn "arn:aws:execute-api:us-east-1:${ACCOUNT_ID}:$REST_API_ID/*/*/*" --region us-east-1
  echo "{ \"Statement\": \"{\\\"Sid\\\":\\\"apigw-login-$(date +%s)\\\",\\\"Effect\\\":\\\"Allow\\\",\\\"Principal\\\":{\\\"Service\\\":\\\"apigateway.amazonaws.com\\\"},\\\"Action\\\":\\\"lambda:InvokeFunction\\\",\\\"Resource\\\":\\\"arn:aws:lambda:us-east-1:${ACCOUNT_ID}:function:$LAMBDA_NAME\\\",\\\"Condition\\\":{\\\"ArnLike\\\":{\\\"AWS:SourceArn\\\":\\\"arn:aws:execute-api:us-east-1:${ACCOUNT_ID}:$REST_API_ID/*/*/*\\\"}}}\" }"

  echo "🆕 Wired new API Gateway to Lambda: $LAMBDA_NAME"
  export REST_API_ID  # Ensure global export
fi