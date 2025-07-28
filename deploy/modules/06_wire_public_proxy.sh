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

echo "📁 Step 6: Wiring /public/{proxy+} route..."

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

# Get or set PARENT_ID (root resource)
if [ -z "${PARENT_ID:-}" ]; then
  if [ "${DRY_RUN:-false}" = "true" ]; then
    echo "🧪 DRY RUN: Skipping: aws apigateway get-resources --rest-api-id $REST_API_ID --query items[0].id --output text"
    PARENT_ID=""
  else
    PARENT_ID=$(aws apigateway get-resources \
      --rest-api-id "$REST_API_ID" \
      --query 'items[0].id' \
      --output text \
      --region us-east-1)
  fi
  export PARENT_ID
fi

# Get or create /public base resource
if [ "${DRY_RUN:-false}" = "true" ]; then
  echo "🧪 DRY RUN: Skipping: aws apigateway get-resources --rest-api-id $REST_API_ID --query items[?path=='/public'].id --output text"
  PUBLIC_ID=""
else
  PUBLIC_ID=$(aws apigateway get-resources \
    --rest-api-id "$REST_API_ID" \
    --query "items[?path=='/public'].id" \
    --output text \
    --region us-east-1)
  # Normalize 'None' to empty string for easier checks
  if [ "$PUBLIC_ID" = "None" ]; then
    PUBLIC_ID=""
  fi
fi

if [ -z "$PUBLIC_ID" ]; then
  echo "🆕 Creating /public base resource..."
  if [ "${DRY_RUN:-false}" = "true" ]; then
    echo "🧪 DRY RUN: Skipping: aws apigateway create-resource --rest-api-id $REST_API_ID --parent-id $PARENT_ID --path-part public"
  else
    PUBLIC_ID=$(aws apigateway create-resource \
      --rest-api-id "$REST_API_ID" \
      --parent-id "$PARENT_ID" \
      --path-part "public" \
      --query 'id' --output text \
      --region us-east-1 2>/dev/null || true)
    if [ -z "$PUBLIC_ID" ] || [ "$PUBLIC_ID" = "None" ]; then
      echo "⚠️  /public already exists. Fetching existing resource ID..."
      PUBLIC_ID=$(aws apigateway get-resources \
        --rest-api-id "$REST_API_ID" \
        --query "items[?path=='/public'].id | [0]" \
        --output text \
        --region us-east-1)
      if [ "$PUBLIC_ID" = "None" ]; then
        PUBLIC_ID=""
      fi
    fi
  fi
fi

# Get or create /public/{proxy+}
if [ "${DRY_RUN:-false}" = "true" ]; then
  echo "🧪 DRY RUN: Skipping: aws apigateway get-resources --rest-api-id $REST_API_ID --query items[?path=='/public/{proxy+}'].id --output text"
  PUBLIC_PROXY_ID=""
else
  PUBLIC_PROXY_ID=$(aws apigateway get-resources \
    --rest-api-id "$REST_API_ID" \
    --query "items[?path=='/public/{proxy+}'].id" \
    --output text \
    --region us-east-1)
  if [ "$PUBLIC_PROXY_ID" = "None" ]; then
    PUBLIC_PROXY_ID=""
  fi
fi

if [ -z "$PUBLIC_PROXY_ID" ]; then
  echo "🆕 Creating /public/{proxy+} resource..."
  if [ "${DRY_RUN:-false}" = "true" ]; then
    echo "🧪 DRY RUN: Skipping: aws apigateway create-resource --rest-api-id $REST_API_ID --parent-id $PUBLIC_ID --path-part {proxy+}"
  else
    PUBLIC_PROXY_ID=$(aws apigateway create-resource \
      --rest-api-id "$REST_API_ID" \
      --parent-id "$PUBLIC_ID" \
      --path-part "{proxy+}" \
      --query 'id' --output text \
      --region us-east-1 2>/dev/null || true)
    if [ -z "$PUBLIC_PROXY_ID" ] || [ "$PUBLIC_PROXY_ID" = "None" ]; then
      echo "⚠️  /public/{proxy+} already exists. Fetching existing resource ID..."
      PUBLIC_PROXY_ID=$(aws apigateway get-resources \
        --rest-api-id "$REST_API_ID" \
        --query "items[?path=='/public/{proxy+}'].id | [0]" \
        --output text \
        --region us-east-1)
      if [ "$PUBLIC_PROXY_ID" = "None" ]; then
        PUBLIC_PROXY_ID=""
      fi
    fi
  fi
else
  echo "✅ /public/{proxy+} already exists."
fi

# Attach ANY method
if [ "${DRY_RUN:-false}" = "true" ]; then
  echo "🧪 DRY RUN: Skipping: aws apigateway put-method --rest-api-id $REST_API_ID --resource-id $PUBLIC_PROXY_ID"
else
  aws apigateway put-method \
    --rest-api-id "$REST_API_ID" \
    --resource-id "$PUBLIC_PROXY_ID" \
    --http-method ANY \
    --authorization-type "NONE" \
    --region us-east-1 || true
fi

# Set Lambda proxy integration
if [ "${DRY_RUN:-false}" = "true" ]; then
  echo "🧪 DRY RUN: Skipping: aws apigateway put-integration --rest-api-id $REST_API_ID --resource-id $PUBLIC_PROXY_ID"
else
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region us-east-1)
  aws apigateway put-integration \
    --rest-api-id "$REST_API_ID" \
    --resource-id "$PUBLIC_PROXY_ID" \
    --http-method ANY \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:${ACCOUNT_ID}:function:$LAMBDA_NAME/invocations \
    --region us-east-1 || true
fi

# Grant invoke permissions
if [ "${DRY_RUN:-false}" = "true" ]; then
  echo "🧪 DRY RUN: Skipping: aws lambda add-permission --function-name $LAMBDA_NAME"
else
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region us-east-1)
  aws lambda add-permission \
    --function-name "$LAMBDA_NAME" \
    --statement-id "publicproxy-$(date +%s)" \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn arn:aws:execute-api:us-east-1:${ACCOUNT_ID}:$REST_API_ID/*/*/public/* \
    --region us-east-1 || true
fi

echo "✅ Wired /public/{proxy+} route successfully."